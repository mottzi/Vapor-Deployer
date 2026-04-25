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

        for (index, step) in steps.enumerated() {
            printStepHeader(console: context.console, title: step.title, index: index + 1, total: steps.count)
            try await step.run()
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

    func printStepHeader(console: any Console, title: String, index: Int, total: Int) {
        console.newLine()
        console.ruler("[\(index)/\(total)] \(title)", color: .cyan)
    }

}
