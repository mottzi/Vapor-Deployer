import Vapor
import Foundation

/// Starts the updated service and verifies it runs stably.
struct StartServiceStep: UpdateStep {

    let context: UpdateContext
    let console: any Console

    let title = "Starting service"

    func run() async throws {

        guard context.releaseVersion != context.currentVersion else { return }

        console.print("Starting service '\(context.serviceName)'.")
        
        let config = try Configuration.load()
        let manager = config.serviceManager.makeManager()
        
        try await manager.start(product: context.serviceName)

        let finalStatus = await waitForStableStatus(manager: manager)
        guard finalStatus.isRunning else { throw UpdateCommand.Error.restartVerificationFailed(finalStatus.label) }
    }

}

extension StartServiceStep {

    /// Waits through transient service states so the command judges the final service state instead of a race.
    private func waitForStableStatus(manager: any ServiceManager) async -> ServiceStatus {
        for _ in 0..<10 {
            let status = await manager.status(product: context.serviceName)
            let isStableStatus = status.isRunning || !status.isTransitioning
            if isStableStatus { return status }

            try? await Task.sleep(for: .milliseconds(500))
        }

        return await manager.status(product: context.serviceName)
    }

}
