import Vapor

/// Lists deployment rows or promotes an exact SHA when a selector is provided.
struct DeployCommand: AnyAsyncCommand {

    var help: String { "List deployments or deploy a selected commit." }

    func run(using context: inout CommandContext) async throws {

        let args = context.input.arguments
        context.input.arguments = []

        let parsed = try DeploymentCLI.parse(args)
        try DeploymentCLI.validateFlags(parsed, allowed: ["--testing", "-t", "--skip-tests", "--yes", "--no-logs"])

        let (config, engine) = try await DeploymentCLI.runtime(from: context)

        switch parsed.positionals.count {
        case 0:
            try await DeploymentCLI.printDeploymentList(config: config, app: context.application, console: context.console)

        case 1:
            let selector = parsed.positionals[0]
            if let known = try? await DeploymentSelector.resolveExisting(selector, config: config, app: context.application),
               known.isLive {
                context.console.output("\(known.shortSHA) is already live.")
                return
            }

            let policy = try DeploymentCLI.testPolicy(parsed: parsed, target: config.target)
            let options = DeploymentEngine.Options(
                testPolicy: policy,
                consoleSink: DeploymentCLI.consoleSink(parsed: parsed, console: context.console)
            )

            try await DeploymentCLI.runLocked(context: context) {
                let deployment = try await DeploymentSelector.resolve(selector, config: config, app: context.application, allowCreate: true)
                if deployment.isLive {
                    context.console.output("\(deployment.shortSHA) is already live.")
                    return
                }
                try await engine.run(action: .deploy, deployment: deployment, options: options)
            }

        default:
            throw DeploymentCLI.CLIError.usage("Usage: deployerctl deploy [sha] [--testing|-t] [--skip-tests --yes] [--no-logs]")
        }
    }

}
