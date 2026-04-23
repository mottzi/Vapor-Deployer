import Vapor

/// Prints the active deployer version for operators and wrapper scripts.
struct VersionCommand: AsyncCommand {

    struct Signature: CommandSignature {}

    var help: String { "Prints the deployed deployer version." }

    func run(using context: CommandContext, signature: Signature) async throws {
        context.console.print(await DeployerVersion.current())
    }

}
