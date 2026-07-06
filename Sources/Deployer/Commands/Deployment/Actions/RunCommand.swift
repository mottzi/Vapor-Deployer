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
            throw DeploymentCLI.CLIError.usage("Usage: deployerctl run <sha> [--skip-health-check]")
        }

        let (config, engine) = try await DeploymentCLI.runtime(from: context)
        let deployment = try await DeploymentSelector.resolveExisting(parsed.positionals[0], config: config, app: context.application)

        let options = OperationEngine.Options(
            skipHealthCheck: parsed.flags.contains("--skip-health-check")
        )

        try await DeploymentCLI.runLocked(context: context) {
            try await engine.run(action: .runSavedBinary, deployment: deployment, options: options)
        }
    }

}
