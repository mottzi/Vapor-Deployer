import Vapor

/// Deploys a selected commit SHA.
struct DeployCommand: AnyAsyncCommand {

    var help: String { "Deploy a selected commit." }

    /// Parses CLI arguments, initializes the headless environment, and executes the deployment.
    func run(using context: inout CommandContext) async throws {

        let args = context.input.arguments
        context.input.arguments = []

        let parsed = try DeploymentCLI.parse(args)
        try DeploymentCLI.validateFlags(parsed, allowed: ["--testing", "-t", "--skip-tests", "--yes", "--no-logs"])

        guard parsed.positionals.count == 1 else {
            throw DeploymentCLI.CLIError.usage(
                "Usage: deployerctl deploy <sha> [--testing|-t] [--skip-tests --yes] [--no-logs]"
            )
        }

        let (config, engine) = try await DeploymentCLI.runtime(from: context)

        try await deployCommit(
            parsed.positionals[0],
            parsed: parsed,
            context: context,
            config: config,
            engine: engine
        )
    }
}

extension DeployCommand {

    /// Evaluates the target commit against the live environment and executes the promotion within the global cross-process lock if the commit is eligible.
    private func deployCommit(
        _ selector: String,
        parsed: DeploymentCLI.ParsedArguments,
        context: CommandContext,
        config: Configuration,
        engine: OperationEngine
    ) async throws {
        
        let known = try? await DeploymentSelector.resolveExisting(
            selector,
            config: config,
            app: context.application
        )

        if let known, known.isLive {
            context.console.output("\(known.shortSHA) is already live.")
            return
        }

        let policy = try DeploymentCLI.testPolicy(parsed: parsed, target: config.target)
        let options = OperationEngine.Options(
            testPolicy: policy,
            consoleSink: DeploymentCLI.consoleSink(parsed: parsed, console: context.console)
        )

        try await DeploymentCLI.runLocked(context: context) {
            let deployment = try await DeploymentSelector.resolve(
                selector,
                config: config,
                app: context.application,
                allowCreate: true
            )
            if deployment.isLive {
                context.console.output("\(deployment.shortSHA) is already live.")
                return
            }
            try await engine.run(action: .deploy, deployment: deployment, options: options)
        }
    }

}
