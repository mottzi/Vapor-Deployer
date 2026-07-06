import Vapor
import NIOCore
import NIOPosix

extension OperationWorker {
    
    /// Polls the target deployment to ensure it responds to health checks consistently over the configured settle duration.
    func verifyHealth() async throws {
        
        let port = target.appPort
        let limit = target.resolvedHealthCheckMaxRetries
        let intervalMs = target.resolvedHealthCheckIntervalMs
        let timeoutMs = target.resolvedHealthCheckTimeoutMs
        let settleSeconds = target.settleDurationSeconds
        
        if let path = target.healthCheckPath {
            await stream?.appendLabel("Verifying Health (HTTP GET \(path))")
        } else {
            await stream?.appendLabel("Verifying Health (TCP)")
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
                isHealthy = await checkTCPHealth(port: port, timeoutMs: timeoutMs)
            }
            
            let attemptPad = attempt < 10 ? " " : ""
            if isHealthy {
                let now = Date.now
                let healthySince = firstHealthyResponseAt ?? now
                firstHealthyResponseAt = healthySince
                
                let duration = now.timeIntervalSince(healthySince)
                await stream?.append("\(attemptPad)[\(attempt)/\(limit)]: healthy   (settled: \(String(format: "%.1f", duration))s / \(settleSeconds)s)\n")
                
                if duration >= settleSeconds {
                    await stream?.append("\nDeployment healthy (\(deployment.commitID.prefix(7)))\n")
                    return
                }
            } else {
                firstHealthyResponseAt = nil
                lastError = target.healthCheckPath != nil ? "HTTP status check failed" : "TCP port connection refused"
                await stream?.append("\(attemptPad)[\(attempt)/\(limit)]: unhealthy\n")
            }
            
            attempt += 1
            try await Task.sleep(for: .milliseconds(intervalMs))
        }
        
        throw Error.deploymentFailed("Health check timed out: \(lastError)")
    }
    
}

extension OperationWorker {

    /// Performs an HTTP GET request to verify the application is actively serving traffic on the specified route.
    private func checkHTTPHealth(path: String, port: Int, timeoutMs: Int) async -> Bool {
        do {
            let url = URI(string: "http://127.0.0.1:\(port)\(path)")
            let response = try await app.client.get(url)
            
            return response.status.code >= 200 && response.status.code < 400
        } catch {
            return false
        }
    }

    /// Attempts a non-blocking TCP connection to confirm the application process is listening on the assigned port.
    private func checkTCPHealth(port: Int, timeoutMs: Int) async -> Bool {
        
        let bootstrap = ClientBootstrap(group: app.eventLoopGroup)
            .connectTimeout(.milliseconds(Int64(timeoutMs)))

        guard let channel = try? await bootstrap.connect(host: "127.0.0.1", port: port).get() else { return false }
        
        try? await channel.close().get()
        
        return true
    }

}
