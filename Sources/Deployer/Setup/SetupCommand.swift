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
            RuntimeConfigStep.self,
            StartServicesStep.self,
            HealthStep.self,
            NginxStep.self,
            TLSStep.self,
            DeployerctlStep.self,
            WebhookStep.self,
            SummaryStep.self,
        ]

        let steps = stepTypes.map { $0.init(context: setupContext, console: context.console) }

        context.console.banner()

        for (index, step) in steps.enumerated() {
            step.printHeader(index: index + 1, total: steps.count)
            try await step.run()
        }
    }

}
