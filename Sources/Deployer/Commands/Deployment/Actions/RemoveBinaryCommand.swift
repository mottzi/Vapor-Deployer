import Vapor

/// Removes a saved binary and returns the deployment row to pushed state.
struct RemoveBinaryCommand: AnyAsyncCommand {

    var help: String { "Remove a saved deployment binary." }

    /// Confirms intent and runs the binary removal under the global lock to return the row to a pushed state.
    func run(using context: inout CommandContext) async throws {

        let args = context.input.arguments
        context.input.arguments = []

        let parsed = try DeploymentCLI.parse(args)
        try DeploymentCLI.validateFlags(parsed, allowed: ["--yes"])
        guard parsed.positionals.count == 1 else {
            throw DeploymentCLI.CLIError.usage("Usage: deployerctl remove-binary <sha> [--yes]")
        }

        let (config, engine) = try await DeploymentCLI.runtime(from: context)
        let deployment = try await DeploymentSelector.resolveExisting(parsed.positionals[0], config: config, app: context.application)
        try DeploymentCLI.confirmIfNeeded("Remove saved binary for \(deployment.shortSHA)?", parsed: parsed, console: context.console)

        try await DeploymentCLI.runLocked(context: context) {
            try await engine.run(action: .removeBinary, deployment: deployment)
        }
    }

}
