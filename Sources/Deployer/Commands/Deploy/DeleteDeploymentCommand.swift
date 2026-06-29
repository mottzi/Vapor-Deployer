import Vapor

/// Deletes a non-live deployment row.
struct DeleteDeploymentCommand: AnyAsyncCommand {

    var help: String { "Delete a non-live deployment row." }

    func run(using context: inout CommandContext) async throws {

        let args = context.input.arguments
        context.input.arguments = []

        let parsed = try DeploymentCLI.parse(args)
        try DeploymentCLI.validateFlags(parsed, allowed: ["--yes"])
        guard parsed.positionals.count == 1 else {
            throw DeploymentCLI.CLIError.usage("Usage: deployerctl delete <sha> [--yes]")
        }

        let (config, engine) = try await DeploymentCLI.runtime(from: context)
        let deployment = try await DeploymentSelector.resolveExisting(parsed.positionals[0], config: config, app: context.application)
        try DeploymentCLI.confirmIfNeeded("Delete deployment \(deployment.shortSHA)?", parsed: parsed, console: context.console)

        try await DeploymentCLI.runLocked(context: context) {
            try await engine.run(action: .delete, deployment: deployment)
        }
    }

}
