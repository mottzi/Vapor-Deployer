# Implementation Plan: Post-Deployment HTTP Health Probes and Auto-Rollback

This plan details the implementation of post-deployment health validation and automated rollback safety nets, as specified in [ADR 0011](file:///Users/berken/Development/Swift/Vapor-Deployer/docs/adr/0011-post-deployment-health-probes-and-auto-rollback.md).

---

## Goal Description
Deployer currently restarts services without verifying that they successfully serve traffic. If a service crashes shortly after boot (flapping), it results in silent production downtime. 
We will implement an automated health probe step in the deployment pipeline. The deployer will query the target port (TCP connection) or a specific URL (HTTP request) recursively until it remains stable for a settle duration (2s). If verification fails or times out (10s), the deployer rolls back the binary swap to the predecessor backup binary, restarts the service, and fails the deployment.

---

## User Review Required
No major architectural blockers exist, as we resolved the design principles during our grilling session. 
> [!IMPORTANT]
> The target application logs will show additional TCP connection attempts and HTTP requests during the 10-second probing window. This is completely expected and will be logged inside the target app's standard log file.

---

## Open Questions
There are no open questions. All design decisions were resolved and recorded in [ADR 0011](file:///Users/berken/Development/Swift/Vapor-Deployer/docs/adr/0011-post-deployment-health-probes-and-auto-rollback.md).

---

## Proposed Changes

### Component: Core Configuration
Modify target schema structures to support user-customizable health check parameters in `deployer.json`.

#### [MODIFY] [TargetConfiguration.swift](file:///Users/berken/Development/Swift/Vapor-Deployer/Sources/Deployer/Configuration/TargetConfiguration.swift)
* Add properties: `healthCheckPath`, `healthCheckIntervalMs`, `healthCheckMaxRetries`, `healthCheckTimeoutMs`.
* Add computed properties for default resolution (500ms intervals, 10s maximum timeout, 2s settle duration).
```swift
    var healthCheckPath: String?
    var healthCheckIntervalMs: Int?
    var healthCheckMaxRetries: Int?
    var healthCheckTimeoutMs: Int?
```
And add resolved defaults in `resolved(relativeTo:)` or as computed properties:
```swift
extension TargetConfiguration {
    var resolvedHealthCheckIntervalMs: Int { healthCheckIntervalMs ?? 500 }
    var resolvedHealthCheckMaxRetries: Int { healthCheckMaxRetries ?? 20 } // 10s total at 500ms intervals
    var resolvedHealthCheckTimeoutMs: Int { healthCheckTimeoutMs ?? 1000 }
    var settleDurationSeconds: Double { 2.0 }
}
```

#### [MODIFY] [DeployerTemplate.swift](file:///Users/berken/Development/Swift/Vapor-Deployer/Sources/Deployer/Commands/Setup/Templates/DeployerTemplate.swift)
* Update `TargetConfiguration` initialization inside `encodeJSON(from:)` to pass `nil` for all new optional parameters, ensuring that the host setup/provisioning command compiles cleanly.
```swift
            target: TargetConfiguration(
                name: context.productName,
                repositoryURL: context.appRepositoryWebURL.isEmpty ? nil : context.appRepositoryWebURL,
                directory: paths.appDirectoryRelative,
                buildMode: context.appBuildMode,
                pusheventPath: paths.webhookPath,
                deploymentMode: context.deploymentMode,
                binaryBehaviour: context.binaryBehaviour,
                appPort: context.appPort,
                branch: context.appBranch,
                testing: context.testing,
                healthCheckPath: nil,
                healthCheckIntervalMs: nil,
                healthCheckMaxRetries: nil,
                healthCheckTimeoutMs: nil
            ),
```

---

### Component: Config CLI Commands
Allow operators to view and update the health check fields dynamically via the CLI.

#### [MODIFY] [ConfigField.swift](file:///Users/berken/Development/Swift/Vapor-Deployer/Sources/Deployer/Commands/Config/ConfigField.swift)
* Register the four new configuration fields in the `ConfigField` enum to make them editable via `deployerctl config`:
```swift
    case targetHealthCheckPath       = "target.healthCheckPath"
    case targetHealthCheckInterval   = "target.healthCheckIntervalMs"
    case targetHealthCheckMaxRetries = "target.healthCheckMaxRetries"
    case targetHealthCheckTimeout    = "target.healthCheckTimeoutMs"
```
* Update `currentValue(in:)` to extract these fields, and update `apply(_:to:)` to parse and apply String/Int value changes dynamically.
```swift
        // Inside currentValue(in:)
        case .targetHealthCheckPath:       config.target.healthCheckPath ?? "nil"
        case .targetHealthCheckInterval:   config.target.healthCheckIntervalMs.map(String.init) ?? "nil"
        case .targetHealthCheckMaxRetries: config.target.healthCheckMaxRetries.map(String.init) ?? "nil"
        case .targetHealthCheckTimeout:    config.target.healthCheckTimeoutMs.map(String.init) ?? "nil"

        // Inside apply(_:to:)
        case .targetHealthCheckPath:
            copy.target.healthCheckPath = input.trimmed == "nil" ? nil : input.trimmed
        case .targetHealthCheckInterval:
            copy.target.healthCheckIntervalMs = input.trimmed == "nil" ? nil : Int(input.trimmed)
        case .targetHealthCheckMaxRetries:
            copy.target.healthCheckMaxRetries = input.trimmed == "nil" ? nil : Int(input.trimmed)
        case .targetHealthCheckTimeout:
            copy.target.healthCheckTimeoutMs = input.trimmed == "nil" ? nil : Int(input.trimmed)
```

---

### Component: Network Probing
Implement a thread-safe connection check leveraging SwiftNIO.

#### [NEW] [SocketProbe.swift](file:///Users/berken/Development/Swift/Vapor-Deployer/Sources/Deployer/Shell/SocketProbe.swift)
* Implement a NIO-based TCP check. Uses `NIOCore` and `NIOPosix` to establish connection and safely awaits future resolution with `.get()`. Ensures clean connection closure to prevent file descriptor leaks.
```swift
import Foundation
import NIOCore
import NIOPosix

enum SocketProbe {
    /// Attempts a non-blocking TCP connection to host:port using SwiftNIO.
    /// Returns true if the port is open and listening within the timeout duration.
    static func canConnect(host: String, port: Int, timeoutMs: Int, on eventLoopGroup: any EventLoopGroup) async -> Bool {
        let bootstrap = ClientBootstrap(group: eventLoopGroup)
            .connectTimeout(.milliseconds(Int64(timeoutMs)))
        
        let channel: Channel
        do {
            channel = try await bootstrap.connect(host: host, port: port).get()
        } catch {
            return false // NIO already cleaned up the socket on a failed connect
        }

        do {
            try await channel.close().get()
        } catch {
            // Close failures don't change the fact that the connection was successfully established.
        }
        return true
    }
}
```

---

### Component: Deployment Worker
Preserve the backup binary until the health probe returns green, and implement recovery routines.

#### [MODIFY] [OperationWorker.swift](file:///Users/berken/Development/Swift/Vapor-Deployer/Sources/Deployer/Operation/OperationEngine/OperationWorker.swift)
* Modify `replaceLiveBinary` to preserve the `.old` binary backup in `deployDir`.
* Implement `cleanupPredecessorBackup()`: deletes the `.old` file on successful deployment validation.
* Implement `restorePredecessorBackup()`: moves the `.old` file back to the live path to roll back the binary swap.
* Implement `verifyHealth()`: loops the TCP / HTTP probe checks, implementing the 2s settle duration check.
```swift
   func cleanupPredecessorBackup() async throws {
       let deployDir = URL(fileURLWithPath: "\(target.directory)/deploy/\(deployment.product)").deletingLastPathComponent().path
       let backupPath = "\(deployDir)/\(deployment.product).old"
       
       let eventLoop = app.eventLoopGroup.any()
       try await app.threadPool.runIfActive(eventLoop: eventLoop) {
           let fileManager = FileManager.default
           if fileManager.fileExists(atPath: backupPath) {
               try fileManager.removeItem(atPath: backupPath)
           }
       }.get()
   }

   func restorePredecessorBackup() async throws {
       let deployPath = "\(target.directory)/deploy/\(deployment.product)"
       let deployDir = URL(fileURLWithPath: deployPath).deletingLastPathComponent().path
       let backupPath = "\(deployDir)/\(deployment.product).old"
       
       let eventLoop = app.eventLoopGroup.any()
       try await app.threadPool.runIfActive(eventLoop: eventLoop) {
           let fileManager = FileManager.default
           if fileManager.fileExists(atPath: backupPath) {
               if fileManager.fileExists(atPath: deployPath) {
                   try fileManager.removeItem(atPath: deployPath)
               }
               try fileManager.moveItem(atPath: backupPath, toPath: deployPath)
           }
       }.get()
   }

   func verifyHealth() async throws {
       let port = target.appPort
       let limit = target.resolvedHealthCheckMaxRetries
       let intervalMs = target.resolvedHealthCheckIntervalMs
       let timeoutMs = target.resolvedHealthCheckTimeoutMs
       let settleSeconds = target.settleDurationSeconds
       
       if let path = target.healthCheckPath {
           await stream?.appendLabel("Verifying Health (HTTP GET \(path))")
       } else {
           await stream?.appendLabel("Verifying Health (TCP Connection)")
       }
       
       var firstHealthyResponseAt: Date?
       let deadline = Date.now.addingTimeInterval(Double(limit * intervalMs) / 1000.0)
       var attempt = 1
       var lastError = "App failed to boot within time limit"

       while Date.now < deadline {
           let isHealthy: Bool
           if let path = target.healthCheckPath {
               isHealthy = await checkHTTPHealth(path: path, port: port, timeoutMs: timeoutMs)
           } else {
               isHealthy = await SocketProbe.canConnect(host: "127.0.0.1", port: port, timeoutMs: timeoutMs, on: app.eventLoopGroup)
           }

           if isHealthy {
               let now = Date.now
               let healthySince = firstHealthyResponseAt ?? now
               firstHealthyResponseAt = healthySince
               
               let duration = now.timeIntervalSince(healthySince)
               await stream?.append("[Attempt \(attempt)/\(limit)]: Healthy (settled: \(String(format: "%.1f", duration))s / \(settleSeconds)s)\n")
               
               if duration >= settleSeconds {
                   await stream?.append("Service stabilized successfully. Deployment verified.\n")
                   return
               }
           } else {
               firstHealthyResponseAt = nil
               lastError = target.healthCheckPath != nil ? "HTTP status check failed" : "TCP port connection refused"
               await stream?.append("[Attempt \(attempt)/\(limit)]: Unhealthy (\(lastError))\n")
           }

           attempt += 1
           try await Task.sleep(for: .milliseconds(intervalMs))
       }

       throw OperationError.deploymentFailed("Health check timed out: \(lastError)")
   }

   private func checkHTTPHealth(path: String, port: Int, timeoutMs: Int) async -> Bool {
       do {
           let url = "http://127.0.0.1:\(port)\(path)"
           let response = try await app.client.get(URI(string: url))
           return response.status.code >= 200 && response.status.code < 400
       } catch {
           return false
       }
   }
```

---

### Component: Pipeline execution & CLI
Wire the probe step into the engine pipeline and add bypass flags to the commands.

#### [MODIFY] [OperationEngine.swift](file:///Users/berken/Development/Swift/Vapor-Deployer/Sources/Deployer/Operation/OperationEngine/OperationEngine.swift)
* Add `skipHealthCheck: Bool` to `Options`.
```swift
    struct Options: Sendable {
        var testPolicy: TestPolicy = .configured
        var consoleSink: OperationOutputConsoleSink?
        var skipHealthCheck: Bool = false
    }
```

#### [MODIFY] [OperationEngine+Pipeline.swift](file:///Users/berken/Development/Swift/Vapor-Deployer/Sources/Deployer/Operation/OperationEngine/OperationEngine+Pipeline.swift)
* Update `runPromote` and `runSavedBinary` to execute `verifyHealth()` right after restarting the service. If health validation throws an error, catch it, run `restorePredecessorBackup()` & restart service, and rethrow to fail the pipeline.
```swift
            try await worker.build()
            try await worker.move()
            try await worker.restart()

            if !options.skipHealthCheck {
                do {
                    try await worker.verifyHealth()
                    try await worker.cleanupPredecessorBackup()
                } catch {
                    await stream?.appendLabel("Health Check Failure")
                    await stream?.append("Deployment unhealthy. Triggering auto-rollback to predecessor...\n")
                    
                    // Recover backup binary & restart back to original predecessor
                    try? await worker.restorePredecessorBackup()
                    try? await worker.restart()
                    throw error
                }
            } else {
                try await worker.cleanupPredecessorBackup()
            }
            
            try await worker.deploy(to: store)
```

#### [MODIFY] [DeployCommand.swift](file:///Users/berken/Development/Swift/Vapor-Deployer/Sources/Deployer/Commands/Deployment/Actions/DeployCommand.swift)
* Allow and parse the `"--skip-health-check"` flag.
```swift
        try DeploymentCLI.validateFlags(parsed, allowed: ["--testing", "-t", "--skip-tests", "--yes", "--no-logs", "--skip-health-check"])
```

#### [MODIFY] [RunCommand.swift](file:///Users/berken/Development/Swift/Vapor-Deployer/Sources/Deployer/Commands/Deployment/Actions/RunCommand.swift)
* Allow and parse the `"--skip-health-check"` flag.
```swift
        try DeploymentCLI.validateFlags(parsed, allowed: ["--skip-health-check"])
```

---

## Verification Plan

### Automated Tests
* Create unit tests for socket probing in `Tests/DeployerTests/SocketProbeTests.swift` if the test suite is configured.

### Manual Verification (To be executed by the Agent via SSH)
The implementing agent will SSH into `root@mottzi.codes` to execute the following verifications:
1. **Healthy Deploy (TCP Default)**:
   * Trigger a deploy (`deployerctl deploy <sha>`).
   * Confirm via SSH logs and `deployerctl status` that the TCP health probe executes successfully, reports success, and deletes the `.old` binary backup in `/home/vapor/apps/mottzi/deploy/mottzi.old`.
2. **Healthy Deploy (HTTP Probe)**:
   * Use `deployerctl config target.healthCheckPath /test` to enable HTTP probing (the target app already exposes `/test` as a valid 200 OK endpoint).
   * Trigger a deploy. Verify from SSH logs and the deployer transcript that HTTP GET probes are executed and succeed.
3. **Auto-Rollback on Port Conflict/Crashes**:
   * Change target config to a broken health path: `deployerctl config target.healthCheckPath /does-not-exist`.
   * Trigger a deploy. Verify via `deployerctl logs deployer` (or by tailing `/home/vapor/deployer/deployer.log`) that:
     - The health check attempts fail and time out after 10 seconds.
     - The deployer automatically restores the predecessor backup binary (`mottzi.old` -> `mottzi`).
     - The service is restarted successfully with the old binary.
     - The deployment row is correctly marked as `.failed`.
4. **Emergency Bypass**:
   * Run `ssh root@mottzi.codes deployerctl deploy <sha> --skip-health-check`.
   * Verify via deploy logs that the health check phase was entirely omitted.
