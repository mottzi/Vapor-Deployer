import Vapor

/// Runs `swift test` for a deployment as a status-preserving audit.
struct TestCommand: AnyAsyncCommand {

    var help: String { "Run tests for a selected deployment." }

    func run(using context: inout CommandContext) async throws {

        let args = context.input.arguments
        context.input.arguments = []

        let parsed = try DeploymentCLI.parse(args)
        try DeploymentCLI.validateFlags(parsed, allowed: ["--no-logs"])
        guard parsed.positionals.count == 1 else {
            throw DeploymentCLI.CLIError.usage("Usage: deployerctl test <sha> [--no-logs]")
        }

        let (config, engine) = try await DeploymentCLI.runtime(from: context)
        let selector = parsed.positionals[0]
        let options = OperationEngine.Options(consoleSink: DeploymentCLI.consoleSink(parsed: parsed, console: context.console))

        try await DeploymentCLI.runLocked(context: context) {
            let deployment = try await DeploymentSelector.resolve(selector, config: config, app: context.application, allowCreate: true)
            try await engine.run(action: .test, deployment: deployment, options: options)
        }
    }

}
