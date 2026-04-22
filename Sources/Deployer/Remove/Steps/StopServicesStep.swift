import Vapor

/// Stops and disables running deployer and app services for both systemd and supervisor.
struct StopServicesStep: RemoveStep {

    let context: RemoveContext
    let console: any Console

    let title = "Stopping services"

    func run() async throws {

        switch context.serviceManagerKind {
        case .systemd: await stopSystemdServices()
        case .supervisor: await stopSupervisorServices()
        }

        console.print("Services stopped.")
    }

}

extension StopServicesStep {

    private func stopSystemdServices() async {

        guard await userExists() else { return }

        await bestEffort("disable systemd units") {
            try await shell.runUserSystemctl("disable --now deployer.service \(context.productName).service")
        }
    }

    private func stopSupervisorServices() async {

        await Shell.run("supervisorctl", ["stop", "deployer"])
        await Shell.run("supervisorctl", ["stop", context.productName])
    }

}

extension StopServicesStep {

    private func userExists() async -> Bool {
        await Shell.run("id", ["-u", context.serviceUser]).exitCode == 0
    }

}
