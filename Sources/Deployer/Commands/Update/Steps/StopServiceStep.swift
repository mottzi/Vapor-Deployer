import Vapor

/// Stops the active deployer service before the final binary swap.
struct StopServiceStep: UpdateStep {

    let context: UpdateContext
    let console: any Console

    let title = "Stopping service"

    func run() async throws {

        guard context.releaseVersion != context.currentVersion else { return }

        console.print("Stopping service '\(context.serviceName)'.")

        let wasRunning = await context.serviceManager.isRunning(product: context.serviceName)
        if wasRunning { try await context.serviceManager.stop(product: context.serviceName) }
    }

}
