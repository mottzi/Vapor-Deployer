import Vapor
import Foundation

struct StartServicesStep: SetupStep {

    let title = "Starting services"

    func run(context: SetupContext, console: any Console) async throws {
        switch context.serviceManagerKind {
        case .systemd:
            try await startSystemdServices(context: context)
        case .supervisor:
            try await startSupervisorServices(context: context)
        }
        console.print("Services enabled and started.")
    }

    private func startSystemdServices(context: SetupContext) async throws {
        let uid = try await context.requireServiceUserUID()
        try await Shell.runThrowing(["loginctl", "enable-linger", context.serviceUser])
        _ = await Shell.run(["systemctl", "start", "user@\(uid).service"])
        try await SetupUserShell.waitForUserBus(uid: uid)
        try await SetupUserShell.runUserSystemctl(context, ["daemon-reload"])
        try await SetupUserShell.runUserSystemctl(context, ["enable", "deployer.service", "\(context.productName).service"])
        try await SetupUserShell.runUserSystemctl(context, ["restart", "deployer.service", "\(context.productName).service"])
    }

    private func startSupervisorServices(context: SetupContext) async throws {
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
