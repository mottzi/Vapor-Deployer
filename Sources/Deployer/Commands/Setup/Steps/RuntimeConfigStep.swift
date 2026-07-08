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
            throw Host.Error.invalidValue("deployer.json", "failed to encode UTF-8 JSON")
        }
        
        try await Host.FileSystem.writeFile(
            json, 
            to: paths.deployerConfig, 
            owner: context.serviceUser, 
            group: context.serviceUser
        )
    }

    private func setupServiceManager() async throws {

        let otherBackend: ServiceBackend = context.serviceBackend == .systemd ? .supervisor : .systemd
        let other = otherBackend.makeConfigurator(shell: shell, paths: paths)
        await other.disable(["deployer", context.productName])
        await other.removeConfigs(for: ["deployer", context.productName])

        switch context.serviceBackend {
        case .systemd:
            try await writeSystemdUnits()
            console.print("Wrote systemd user units.")
        case .supervisor:
            try await writeSupervisorFiles()
            console.print("Wrote Supervisor program files.")
        }
    }

}

extension RuntimeConfigStep {

    private func writeSystemdUnits() async throws {

        let unitDirectory = "\(paths.serviceHome)/.config/systemd/user"
        try await Host.FileSystem.installDirectory(unitDirectory, owner: context.serviceUser, group: context.serviceUser)
        
        try await Host.FileSystem.writeFile(
            try SystemdTemplate.deployerUnit(context: context),
            to: "\(unitDirectory)/deployer.service",
            owner: context.serviceUser,
            group: context.serviceUser
        )
        
        try await Host.FileSystem.writeFile(
            try SystemdTemplate.appUnit(context: context),
            to: "\(unitDirectory)/\(context.productName).service",
            owner: context.serviceUser,
            group: context.serviceUser
        )
    }

    private func writeSupervisorFiles() async throws {
        
        try await Host.FileSystem.writeFile(
            try SupervisorTemplate.deployerProgram(context: context),
            to: "/etc/supervisor/conf.d/deployer.conf"
        )
        
        try await Host.FileSystem.writeFile(
            try SupervisorTemplate.appProgram(context: context),
            to: "/etc/supervisor/conf.d/\(context.productName).conf"
        )
    }

}
