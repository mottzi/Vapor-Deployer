import Vapor

/// Builds a deployment and archives its binary without making it live.
struct BuildCommand: AnyAsyncCommand {

    var help: String { "Build and save a selected deployment binary." }

    /// Resolves the SHA, acquires the lock, and executes a build without promoting to the live environment.
    func run(using context: inout CommandContext) async throws {

        let args = context.input.arguments
        context.input.arguments = []

        let parsed = try DeploymentCLI.parse(args)
        try DeploymentCLI.validateFlags(parsed, allowed: ["--no-logs"])
        guard parsed.positionals.count == 1 else {
            throw DeploymentCLI.Error.usage("Usage: deployerctl build <sha> [--no-logs]")
        }

        let (config, engine) = try await DeploymentCLI.runtime(from: context)
        let selector = parsed.positionals[0]
        let options = OperationEngine.Options(consoleSink: DeploymentCLI.consoleSink(parsed: parsed, console: context.console))

        try await DeploymentCLI.runLocked(context: context) {
            let deployment = try await DeploymentSelector.resolve(selector, config: config, app: context.application, allowCreate: true)
            try await engine.run(action: .build, deployment: deployment, options: options)
        }
    }

}
