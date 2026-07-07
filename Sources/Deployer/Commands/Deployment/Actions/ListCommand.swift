import Vapor

/// Lists deployment records up to a given limit.
struct ListCommand: AnyAsyncCommand {

    var help: String { "List deployments up to a maximum limit." }

    /// Parses CLI arguments, initializes the headless environment, and prints the deployment table.
    func run(using context: inout CommandContext) async throws {

        let args = context.input.arguments
        context.input.arguments = []

        let parsed = try DeploymentCLI.parse(args)
        try DeploymentCLI.validateFlags(parsed, allowed: [])

        var limit = DeploymentCLI.defaultListLimit
        if parsed.positionals.count == 1 {
            guard let customLimit = Int(parsed.positionals[0]), customLimit > 0 else {
                throw DeploymentCLI.Error.usage("Usage: deployerctl list [max]")
            }
            limit = customLimit
        } else if parsed.positionals.count > 1 {
            throw DeploymentCLI.Error.usage("Usage: deployerctl list [max]")
        }

        let config = try await context.application.deployer.useHeadlessRuntime()

        try await DeploymentCLI.printDeploymentList(
            config: config,
            app: context.application,
            console: context.console,
            limit: limit
        )
    }

}
