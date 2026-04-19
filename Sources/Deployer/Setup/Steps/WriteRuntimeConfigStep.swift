import Vapor
import Foundation

struct WriteRuntimeConfigStep: SetupStep {

    let title = "Writing runtime configuration"

    func run(context: SetupContext, console: any Console) async throws {
        let paths = try context.requirePaths()
        let config = try DeployerJSONTemplate.configuration(from: context)
        let data = try config.encodeJSON()
        guard let json = String(data: data, encoding: .utf8) else {
            throw SetupCommand.Error.invalidValue("deployer.json", "failed to encode UTF-8 JSON")
        }
        try await SetupFileSystem.writeFile(json, to: paths.deployerConfig, owner: context.serviceUser, group: context.serviceUser)

        switch context.serviceManagerKind {
        case .systemd:
            try await removeSupervisorFiles(context: context)
            try await writeSystemdUnits(context: context)
            console.print("Wrote systemd user units.")
        case .supervisor:
            try await removeSystemdFiles(context: context)
            try await writeSupervisorFiles(context: context)
            console.print("Wrote Supervisor program files.")
        }
    }

    private func writeSystemdUnits(context: SetupContext) async throws {
        let paths = try context.requirePaths()
        let unitDirectory = "\(paths.serviceHome)/.config/systemd/user"
        try await SetupFileSystem.installDirectory(unitDirectory, owner: context.serviceUser, group: context.serviceUser)
        try await SetupFileSystem.writeFile(
            try SystemdUnitsTemplate.deployerUnit(context: context),
            to: "\(unitDirectory)/deployer.service",
            owner: context.serviceUser,
            group: context.serviceUser
        )
        try await SetupFileSystem.writeFile(
            try SystemdUnitsTemplate.appUnit(context: context),
            to: "\(unitDirectory)/\(context.productName).service",
            owner: context.serviceUser,
            group: context.serviceUser
        )
    }

    private func writeSupervisorFiles(context: SetupContext) async throws {
        try await SetupFileSystem.writeFile(
            try SupervisorConfigTemplate.deployerProgram(context: context),
            to: "/etc/supervisor/conf.d/deployer.conf"
        )
        try await SetupFileSystem.writeFile(
            try SupervisorConfigTemplate.appProgram(context: context),
            to: "/etc/supervisor/conf.d/\(context.productName).conf"
        )
    }

    private func removeSystemdFiles(context: SetupContext) async throws {
        let paths = try context.requirePaths()
        let unitDirectory = "\(paths.serviceHome)/.config/systemd/user"
        _ = try? await UserShell.runUserSystemctl(context, ["disable", "--now", "deployer.service", "\(context.productName).service"])
        try? SetupFileSystem.removeIfPresent("\(unitDirectory)/deployer.service")
        try? SetupFileSystem.removeIfPresent("\(unitDirectory)/\(context.productName).service")
        _ = try? await UserShell.runUserSystemctl(context, ["daemon-reload"])
    }

    private func removeSupervisorFiles(context: SetupContext) async throws {
        _ = await Shell.run(["supervisorctl", "stop", "deployer"])
        _ = await Shell.run(["supervisorctl", "stop", context.productName])
        try? SetupFileSystem.removeIfPresent("/etc/supervisor/conf.d/deployer.conf")
        try? SetupFileSystem.removeIfPresent("/etc/supervisor/conf.d/\(context.productName).conf")
        _ = await Shell.run(["supervisorctl", "reread"])
        _ = await Shell.run(["supervisorctl", "update"])
    }

}
