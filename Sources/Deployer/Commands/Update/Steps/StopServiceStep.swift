import Vapor
import Foundation

/// Stops the active deployer service before the final binary swap.
struct StopServiceStep: UpdateStep {

    let context: UpdateContext
    let console: any Console

    let title = "Stopping service"

    func run() async throws {

        guard context.releaseVersion != context.currentVersion else { return }

        console.print("Stopping service '\(context.serviceName)'.")
        
        let config = try Configuration.load()
        let manager = config.serviceManager.makeManager()
        
        let wasRunning = await manager.isRunning(product: context.serviceName)
        if wasRunning { try await manager.stop(product: context.serviceName) }
    }

}
