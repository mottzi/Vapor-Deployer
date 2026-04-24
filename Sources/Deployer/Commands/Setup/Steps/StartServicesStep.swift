import Vapor

/// Enables and starts the deployment pipeline and target application using the active service manager.
struct StartServicesStep: SetupStep {

    let context: SetupContext
    let console: any Console

    let title = "Starting services"

    func run() async throws {

        let configurator = context.serviceManagerKind.makeConfigurator(shell: shell, paths: paths)
        try await configurator.enableAndStart(["deployer", context.productName])

        console.print("Services enabled and started.")
    }

}
