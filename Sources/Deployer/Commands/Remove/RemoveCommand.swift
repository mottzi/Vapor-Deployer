import Vapor

/// Orchestrates host teardown by running remove steps in a fixed order against one shared context.
struct RemoveCommand: AsyncCommand {

    struct Signature: CommandSignature {}

    var help: String { "Tears down a deployer installation on this host." }

    func run(using context: CommandContext, signature: Signature) async throws {

        try requireRoot()
        try requireUbuntu()

        let removeContext = RemoveContext()

        let stepTypes: [any RemoveStep.Type] = [
            RemoveInputStep.self,
            StopServicesStep.self,
            RemoveServiceFilesStep.self,
            RemoveProxyStep.self,
            RemoveTLSStep.self,
            RemoveDeployerctlStep.self,
            RemoveSSHStep.self,
            RemoveCheckoutsStep.self,
            RemoveUserStep.self,
            RemoveSummaryStep.self,
        ]

        let steps = stepTypes.map { $0.init(context: removeContext, console: context.console) }

        printBanner(to: context.console)

        for (index, step) in steps.enumerated() {
            context.console.stepHeader(title: step.title, index: index + 1, total: steps.count, color: .red)
            try await step.run()
        }
    }

}

private extension RemoveCommand {

    func printBanner(to console: any Console) {
        console.newLine()
        console.ruler(color: .red)
        console.output("  Vapor Deployer · Remove".consoleText(color: .red, isBold: true))
        console.ruler(color: .red)
        console.newLine()
        console.output("  Stops services, removes managed proxy files, and deletes")
        console.output("  the service user created by setup. This is destructive.")
        console.newLine()
    }

}
