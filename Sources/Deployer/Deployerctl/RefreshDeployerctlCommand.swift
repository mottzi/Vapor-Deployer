import Vapor

/// Refreshes the root-owned deployerctl wrapper from the currently running binary's embedded templates.
struct RefreshDeployerctlCommand: AsyncCommand {

    struct Signature: CommandSignature {}

    var help: String { "Refreshes the deployerctl wrapper for update internals." }

    /// Executes the command to refresh deployerctl wrapper scripts using current configuration and system context.
    func run(using context: CommandContext, signature: Signature) async throws {
        
        let config = try Configuration.load()
        let metadata = await ConfigDiscovery.loadDeployerctl()
        let executableURL = try Configuration.getExecutableURL()
        let serviceUser = await ConfigDiscovery.resolveServiceUser(executableURL: executableURL)
       
        let installContext = try DeployerctlInstaller.Context(
            configuration: config,
            metadata: metadata,
            executableURL: executableURL,
            serviceUser: serviceUser
        )

        switch try await DeployerctlInstaller.refresh(context: installContext) {
            case .refreshedDirectly: context.console.print("Refreshed deployerctl wrapper and panel update helper.")
            case .refreshedWithHelper: context.console.print("Refreshed deployerctl wrapper through the panel update helper.")
            case .helperUnavailable: context.console.warning("Skipped deployerctl wrapper refresh: panel update helper is not installed. Run 'sudo \(executableURL.path) refresh-deployerctl' once to enable future panel refreshes.")
        }
    }

}
