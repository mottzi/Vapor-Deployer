import Vapor

/// Stops and disables running deployer and app services for both systemd and supervisor.
struct StopServicesStep: RemoveStep {

    let context: RemoveContext
    let console: any Console

    let title = "Stopping services"

    func run() async throws {

        let configurator = context.serviceManagerKind.makeConfigurator(shell: shell, paths: paths)
        await configurator.disable(["deployer", context.productName])

        console.print("Services stopped.")
    }

}
