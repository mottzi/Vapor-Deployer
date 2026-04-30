import Vapor

/// Orchestrates host provisioning by running setup steps in a fixed order against one shared context.
struct SetupCommand: AsyncCommand {

    struct Signature: CommandSignature {}

    var help: String { "Installs and provisions the deployer on this host." }

    func run(using context: CommandContext, signature: Signature) async throws {

        try requireRoot()
        try requireUbuntu()

        let setupContext = SetupContext()

        let stepTypes: [any SetupStep.Type] = [
            InputStep.self,
            PreflightStep.self,
            PackagesStep.self,
            ServiceUserStep.self,
            StageDeployerStep.self,
            SSHStep.self,
            AppCheckoutStep.self,
            ResolveProductStep.self, 
            SwiftStep.self,
            BuildStep.self,
            CleanupOrphansStep.self,
            RuntimeConfigStep.self,
            StartServicesStep.self,
            HealthStep.self,
            NginxStep.self,
            TLSStep.self,
            CleanupOrphanedTLSLineageStep.self,
            DeployerctlStep.self,
            WebhookStep.self,
            SSHHardeningStep.self,
            SummaryStep.self,
        ]

        let steps = stepTypes.map { $0.init(context: setupContext, console: context.console) }

        printBanner(console: context.console)

        do {
            for (index, step) in steps.enumerated() {
                context.console.stepHeader(title: step.title, index: index + 1, total: steps.count, color: .cyan)
                try await step.run()
            }
            
            if let paths = setupContext.paths {
                let backupPath = paths.installDirectory + ".bak"
                if FileManager.default.fileExists(atPath: backupPath) {
                    try? FileManager.default.removeItem(atPath: backupPath)
                }
            }
        } catch {
            do {
                try await rollbackSetup(context: setupContext, console: context.console, originalError: error)
            } catch let rollbackError {
                context.console.warning("Rollback also encountered an error: \(rollbackError.localizedDescription)")
            }
            throw error
        }
    }

}

private extension SetupCommand {

    func printBanner(console: any Console) {
        console.newLine()
        console.ruler(color: .cyan)
        console.output("  Vapor Deployer · Setup".consoleText(color: .cyan, isBold: true))
        console.ruler(color: .cyan)
        console.newLine()
        console.output("  Installs the deployer + target app, configures services.")
        console.output("  Provisions Nginx + TLS and wires the GitHub webhook.")
        console.newLine()
    }

    func rollbackSetup(context: SetupContext, console: any Console, originalError: Swift.Error) async throws {
        guard let paths = context.paths else { return }
        let backupPath = paths.installDirectory + ".bak"
        
        if FileManager.default.fileExists(atPath: backupPath) {
            console.warning("Setup failed during a mode switch. Rolling back installation...")
            if FileManager.default.fileExists(atPath: paths.installDirectory) {
                try? FileManager.default.removeItem(atPath: paths.installDirectory)
            }
            try? FileManager.default.moveItem(atPath: backupPath, toPath: paths.installDirectory)
            
            if let serviceManager = context.previousMetadata?["SERVICE_MANAGER"],
               let managerKind = ServiceManagerKind(rawValue: serviceManager) {
                do {
                    let manager = try managerKind.makeManager(serviceUser: context.serviceUser)
                    try await manager.start(product: "deployer")
                } catch {
                    console.warning("Rollback restored files, but failed to restart the deployer service.")
                }
            }
        }
    }

}
