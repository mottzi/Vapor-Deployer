import Vapor

struct OperationWorker {
    
    let deployment: Deployment
    let target: TargetConfiguration
    let app: Application
    let stream: OperationOutputStream?
    let environment: [String: String]
    let onStatusChange: @Sendable (ServiceStatus) async -> Void
    
}

extension OperationWorker {

    func checkout() async throws {
        await stream?.appendLabel("git fetch origin \(deployment.branch)")
        try await Shell.runStreaming(
            "git", ["fetch", "origin", deployment.branch],
            directory: target.directory,
            environment: environment,
            onOutput: { chunk in await stream?.append(chunk) }
        )

        await stream?.appendLabel("git checkout --detach -f \(deployment.commitID.prefix(7))")
        try await Shell.runStreaming(
            "git", ["checkout", "--detach", "-f", deployment.commitID],
            directory: target.directory,
            environment: environment,
            onOutput: { chunk in await stream?.append(chunk) }
        )
    }

    @discardableResult
    func build() async throws -> String {
        await stream?.appendLabel("swift build -c \(target.buildMode)")
        return try await Shell.runStreaming(
            "swift", ["build", "-c", target.buildMode],
            directory: target.directory,
            environment: environment,
            onOutput: { chunk in await stream?.append(chunk) }
        )
    }

    @discardableResult
    func test() async throws -> String {
        // Isolated `.build-tests` scratch path so `-enable-testing` artifacts from `swift test`
        // never overwrite the production `.build/` cache used by `swift build` — see ADR 0003.
        // The scratch flag is an implementation detail not surfaced in the user-visible label.
        await stream?.appendLabel("swift test -c \(target.buildMode)")
        return try await Shell.runStreaming(
            "swift", ["test", "-c", target.buildMode, "--scratch-path", ".build-tests"],
            directory: target.directory,
            environment: environment,
            onOutput: { chunk in await stream?.append(chunk) }
        )
    }

    func restart(overrideSHA: String? = nil) async throws {
        let manager = app.deployer.serviceManager
        let status = await manager.status(product: deployment.product)
        await onStatusChange(status.isRunning ? .stopping : .starting)

        try await manager.restart(product: deployment.product)
        await onStatusChange(.starting)

        let finalStatus = await manager.status(product: deployment.product)
        await onStatusChange(finalStatus)
        let sha = overrideSHA ?? String(deployment.commitID.prefix(7))
        await stream?.append("Restart service (\(sha))\n")
    }

    func move() async throws {
        await stream?.appendLabel("deployer")
        await stream?.append("Install binary (\(deployment.commitID.prefix(7)))\n")

        let buildPath = "\(target.directory)/.build/\(target.buildMode)/\(deployment.product)"
        let deployPath = "\(target.directory)/deploy/\(deployment.product)"
        try await replaceLiveBinary(from: buildPath, to: deployPath, transfer: .move)
    }

    func restore(from store: DeploymentBinaryStore) async throws {
        await stream?.appendLabel("deployer")
        await stream?.append("Restore binary (\(deployment.commitID.prefix(7)))\n")

        let binaryPath = try store.binaryPath(for: deployment)
        try await replaceLiveBinary(from: binaryPath, to: store.liveBinaryPath, transfer: .copy)
    }

    func save(to store: DeploymentBinaryStore) async throws {
        await stream?.appendLabel("deployer")
        try await store.storeBuiltBinary(for: deployment, app: app, manually: true)
        await stream?.append("Archive binary (\(deployment.commitID.prefix(7)))\n")
    }

    func deploy(to store: DeploymentBinaryStore) async throws {
        await stream?.appendLabel("deployer")
        try await store.storeLiveBinary(for: deployment, app: app, manually: false)
        await stream?.append("Archive binary (\(deployment.commitID.prefix(7)))\n")
    }

}

extension OperationWorker {

    private enum BinaryTransfer {
        case copy
        case move
    }

    /// Atomically swaps the live binary at `deployPath` with the source, keeping a `.old` backup for rollback on failure.
    private func replaceLiveBinary(from sourcePath: String, to deployPath: String, transfer: BinaryTransfer) async throws {

        let eventLoop = app.eventLoopGroup.any()
        let threadPool = app.threadPool

        let deployDir = URL(fileURLWithPath: deployPath).deletingLastPathComponent().path
        let backupPath = "\(deployDir)/\(deployment.product).old"

        try await threadPool.runIfActive(eventLoop: eventLoop) {
            let fileManager = FileManager.default
            try fileManager.createDirectory(atPath: deployDir, withIntermediateDirectories: true)

            guard fileManager.fileExists(atPath: sourcePath) else {
                throw Error.binaryNotFound(sourcePath)
            }
            if fileManager.fileExists(atPath: backupPath) {
                try fileManager.removeItem(atPath: backupPath)
            }
            if fileManager.fileExists(atPath: deployPath) {
                try fileManager.moveItem(atPath: deployPath, toPath: backupPath)
            }

            do {
                switch transfer {
                    case .copy: try fileManager.copyItem(atPath: sourcePath, toPath: deployPath)
                    case .move: try fileManager.moveItem(atPath: sourcePath, toPath: deployPath)
                }
            } catch {
                let moveError = error
                if fileManager.fileExists(atPath: backupPath) {
                    do {
                        if fileManager.fileExists(atPath: deployPath) {
                            try fileManager.removeItem(atPath: deployPath)
                        }
                        try fileManager.moveItem(atPath: backupPath, toPath: deployPath)
                        app.logger.error("replaceLiveBinary failed for commit \(deployment.commitID.prefix(7)). Rollback successful: \(moveError.localizedDescription)")
                    } catch {
                        app.logger.error("replaceLiveBinary failed for commit \(deployment.commitID.prefix(7)). Rollback failed: \(error.localizedDescription). Original error: \(moveError.localizedDescription)")
                        throw Error.deploymentAndRollbackFailed(moveError.localizedDescription, error.localizedDescription)
                    }
                } else {
                    app.logger.error("replaceLiveBinary failed for commit \(deployment.commitID.prefix(7)). No rollback possible: \(moveError.localizedDescription)")
                }

                throw Error.deploymentFailed(moveError.localizedDescription)
            }
        }.get()
    }

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
                    await stream?.append("\nDeployment healthy (\(deployment.commitID.prefix(7)))\n")
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

        throw Error.deploymentFailed("Health check timed out: \(lastError)")
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

}
