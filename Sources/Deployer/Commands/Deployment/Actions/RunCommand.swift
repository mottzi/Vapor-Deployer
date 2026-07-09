import Vapor

/// Restores and runs a saved deployment binary.
struct RunCommand: AnyAsyncCommand {

    var help: String { "Run the saved binary for a selected deployment." }

    /// Resolves the existing deployment and instructs the engine to run its saved binary under the global lock.
    func run(using context: inout CommandContext) async throws {

        let args = context.input.arguments
        context.input.arguments = []

        let parsed = try DeploymentCLI.parse(args)
        try DeploymentCLI.validateFlags(parsed, allowed: ["--skip-health-check"])
        guard parsed.positionals.count == 1 else {
            throw DeploymentCLI.Error.usage("Usage: deployerctl run <sha> [--skip-health-check]")
        }

        let (config, engine) = try await DeploymentCLI.runtime(from: context)
        let selector = parsed.positionals[0]
        let known = try await DeploymentSelector.resolveExisting(selector, config: config, app: context.application)

        if known.isLive {
            DeploymentCLI.printAlreadyLive(known, console: context.console)
            return
        }

        let options = OperationEngine.Options(
            skipHealthCheck: parsed.flags.contains("--skip-health-check")
        )

        try await DeploymentCLI.runLocked(context: context) {
            let deployment = try await DeploymentSelector.resolveExisting(selector, config: config, app: context.application)
            if deployment.isLive {
                DeploymentCLI.printAlreadyLive(deployment, console: context.console)
                return
            }
            try await engine.run(action: .runSavedBinary, deployment: deployment, options: options)
        }
    }

}
