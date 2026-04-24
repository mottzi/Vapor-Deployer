import Vapor

/// Starts the updated service and verifies it runs stably.
struct StartServiceStep: UpdateStep {

    let context: UpdateContext
    let console: any Console

    let title = "Starting service"

    func run() async throws {

        guard context.releaseVersion != context.currentVersion else { return }

        console.print("Starting service '\(context.serviceName)'.")
        
        let config = try Configuration.load()
        let manager = config.serviceManager.makeManager(serviceUser: context.managerServiceUser)
        
        try await manager.start(product: context.serviceName)

        let finalStatus = await manager.waitForStableStatus(product: context.serviceName)
        guard finalStatus.isRunning else { throw UpdateCommand.Error.restartVerificationFailed(finalStatus.label) }
    }

}
