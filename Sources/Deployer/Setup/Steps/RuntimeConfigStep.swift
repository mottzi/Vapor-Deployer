import Vapor

/// Generates and persists the deployer's configuration JSON and the appropriate process manager files (systemd or Supervisor).
struct RuntimeConfigStep: SetupStep {

    let context: SetupContext
    let console: any Console

    let title = "Writing runtime configuration"

    func run() async throws {

        try await writeDeployerConfig()
        try await setupServiceManager()
    }

}

extension RuntimeConfigStep {

    private func writeDeployerConfig() async throws {

        guard let json = try DeployerTemplate.encodeJSON(from: context) else {
            throw SystemError.invalidValue("deployer.json", "failed to encode UTF-8 JSON")
        }
        
        try await SystemFileSystem.writeFile(
            json, 
            to: paths.deployerConfig, 
            owner: context.serviceUser, 
            group: context.serviceUser
        )
    }

    private func setupServiceManager() async throws {

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

}

extension RuntimeConfigStep {

    private func writeSystemdUnits() async throws {

        let unitDirectory = "\(paths.serviceHome)/.config/systemd/user"
        try await SystemFileSystem.installDirectory(unitDirectory, owner: context.serviceUser, group: context.serviceUser)
        
        try await SystemFileSystem.writeFile(
            try SystemdTemplate.deployerUnit(context: context),
            to: "\(unitDirectory)/deployer.service",
            owner: context.serviceUser,
            group: context.serviceUser
        )
        
        try await SystemFileSystem.writeFile(
            try SystemdTemplate.appUnit(context: context),
            to: "\(unitDirectory)/\(context.productName).service",
            owner: context.serviceUser,
            group: context.serviceUser
        )
    }

    private func writeSupervisorFiles() async throws {
        
        try await SystemFileSystem.writeFile(
            try SupervisorTemplate.deployerProgram(context: context),
            to: "/etc/supervisor/conf.d/deployer.conf"
        )
        
        try await SystemFileSystem.writeFile(
            try SupervisorTemplate.appProgram(context: context),
            to: "/etc/supervisor/conf.d/\(context.productName).conf"
        )
    }

    private func removeSystemdFiles() async throws {

        let unitDirectory = "\(paths.serviceHome)/.config/systemd/user"
        _ = try? await shell.runUserSystemctl("disable", ["--now", "deployer.service", "\(context.productName).service"])
        
        try? SystemFileSystem.removeIfPresent("\(unitDirectory)/deployer.service")
        try? SystemFileSystem.removeIfPresent("\(unitDirectory)/\(context.productName).service")
        
        _ = try? await shell.runUserSystemctl("daemon-reload")
    }

    private func removeSupervisorFiles() async throws {
        
        _ = await Shell.run("supervisorctl", ["stop", "deployer"])
        _ = await Shell.run("supervisorctl", ["stop", context.productName])
        
        try? SystemFileSystem.removeIfPresent("/etc/supervisor/conf.d/deployer.conf")
        try? SystemFileSystem.removeIfPresent("/etc/supervisor/conf.d/\(context.productName).conf")
        
        _ = await Shell.run("supervisorctl", ["reread"])
        _ = await Shell.run("supervisorctl", ["update"])
    }

}
