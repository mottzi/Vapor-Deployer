import Vapor
import Foundation

struct StartServicesStep: SetupStep {

    let context: SetupContext
    let console: any Console

    let title = "Starting services"

    func run() async throws {
        switch context.serviceManagerKind {
        case .systemd:
            try await startSystemdServices()
        case .supervisor:
            try await startSupervisorServices()
        }
        console.print("Services enabled and started.")
    }

    private func startSystemdServices() async throws {
        let uid = try await context.requireServiceUserUID()
        try await Shell.runThrowing(["loginctl", "enable-linger", context.serviceUser])
        _ = await Shell.run(["systemctl", "start", "user@\(uid).service"])
        try await SetupShell.waitForUserBus(uid: uid)
        try await shell.runUserSystemctl(["daemon-reload"])
        try await shell.runUserSystemctl(["enable", "deployer.service", "\(context.productName).service"])
        try await shell.runUserSystemctl(["restart", "deployer.service", "\(context.productName).service"])
    }

    private func startSupervisorServices() async throws {
        try await Shell.runThrowing(["systemctl", "enable", "--now", "supervisor"])
        try await Shell.runThrowing(["supervisorctl", "reread"])
        try await Shell.runThrowing(["supervisorctl", "update"])
        try await restartOrStartSupervisorProgram("deployer")
        try await restartOrStartSupervisorProgram(context.productName)
    }

    private func restartOrStartSupervisorProgram(_ program: String) async throws {
        let restart = await Shell.run(["supervisorctl", "restart", program])
        if restart.exitCode == 0 { return }
        try await Shell.runThrowing(["supervisorctl", "start", program])
    }

}
