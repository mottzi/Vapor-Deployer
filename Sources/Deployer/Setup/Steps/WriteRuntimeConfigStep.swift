import Vapor

struct WriteRuntimeConfigStep: SetupStep {

    let context: SetupContext
    let console: any Console

    let title = "Writing runtime configuration"

    func run() async throws {
        
        let paths = try context.requirePaths()
        guard let json = try DeployerTemplate.encodeJSON(from: context)
        else { throw SetupCommand.Error.invalidValue("deployer.json", "failed to encode UTF-8 JSON") }
        try await SetupFileSystem.writeFile(json, to: paths.deployerConfig, owner: context.serviceUser, group: context.serviceUser)

        switch context.serviceManagerKind {
        case .systemd:
            try await removeSupervisorFiles()
            try await writeSystemdUnits()
            console.print("Wrote systemd user units.")
            
        case .supervisor:
            try await removeSystemdFiles()
            try await writeSupervisorFiles()
            console.print("Wrote Supervisor program files.")
        }
    }

    private func writeSystemdUnits() async throws {
        
        let paths = try context.requirePaths()
        let unitDirectory = "\(paths.serviceHome)/.config/systemd/user"
        try await SetupFileSystem.installDirectory(unitDirectory, owner: context.serviceUser, group: context.serviceUser)
        
        try await SetupFileSystem.writeFile(
            try SystemdTemplate.deployerUnit(context: context),
            to: "\(unitDirectory)/deployer.service",
            owner: context.serviceUser,
            group: context.serviceUser
        )
        
        try await SetupFileSystem.writeFile(
            try SystemdTemplate.appUnit(context: context),
            to: "\(unitDirectory)/\(context.productName).service",
            owner: context.serviceUser,
            group: context.serviceUser
        )
    }

    private func writeSupervisorFiles() async throws {
        
        try await SetupFileSystem.writeFile(
            try SupervisorTemplate.deployerProgram(context: context),
            to: "/etc/supervisor/conf.d/deployer.conf"
        )
        
        try await SetupFileSystem.writeFile(
            try SupervisorTemplate.appProgram(context: context),
            to: "/etc/supervisor/conf.d/\(context.productName).conf"
        )
    }

    private func removeSystemdFiles() async throws {
        
        let paths = try context.requirePaths()
        let unitDirectory = "\(paths.serviceHome)/.config/systemd/user"
        _ = try? await shell.runUserSystemctl("disable", ["--now", "deployer.service", "\(context.productName).service"])
        try? SetupFileSystem.removeIfPresent("\(unitDirectory)/deployer.service")
        try? SetupFileSystem.removeIfPresent("\(unitDirectory)/\(context.productName).service")
        _ = try? await shell.runUserSystemctl("daemon-reload")
    }

    private func removeSupervisorFiles() async throws {
        
        _ = await Shell.run("supervisorctl", ["stop", "deployer"])
        _ = await Shell.run("supervisorctl", ["stop", context.productName])
        try? SetupFileSystem.removeIfPresent("/etc/supervisor/conf.d/deployer.conf")
        try? SetupFileSystem.removeIfPresent("/etc/supervisor/conf.d/\(context.productName).conf")
        _ = await Shell.run("supervisorctl", ["reread"])
        _ = await Shell.run("supervisorctl", ["update"])
    }

}
