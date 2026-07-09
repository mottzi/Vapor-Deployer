import Vapor
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Performs an in-place update of the deployed installation by downloading the latest GitHub release.
struct UpdateCommand: AsyncCommand {

    struct Signature: CommandSignature {}

    var help: String { "Updates the deployer installation." }

    /// Downloads the latest release, extracts it, and does a stop / swap / start with rollback on failure.
    func run(using context: CommandContext, signature: Signature) async throws {
        try await runPipeline(context: context)
    }

    private func runPipeline(context: CommandContext) async throws {

        context.application.logger.info("Running self-update pipeline...")
        
        let executableURL = try Configuration.getExecutableURL()
        let installDirectory = executableURL.deletingLastPathComponent()
        let executableName = executableURL.lastPathComponent

        guard !executableName.isEmpty else { throw Error.invalidExecutablePath(executableURL.path) }

        let config = try Configuration.load()

        // User-typed shell invocations verify the running server is in `.ready` phase before proceeding.
        // Panel-spawned children carry `DEPLOYER_INTERNAL_UPDATE=1` and skip the query — their parent
        // already vetted state and is itself the source of `.updating`. Connection-refused is treated
        // as "server not running" → proceed (recovery path). See `docs/adr/0005-cli-server-state-channel.md`.
        if ProcessInfo.processInfo.environment["DEPLOYER_INTERNAL_UPDATE"] != "1" {
            try await preflightControlQuery(
                app: context.application,
                config: config,
                installDirectory: installDirectory,
                console: context.console
            )
        }

        let operationLock = try OperationLock.acquire()
        defer { operationLock.release() }
        
        let updateLock = try UpdateLock.acquire()
        defer { updateLock.release() }

        let serviceUser = await ConfigDiscovery.resolveServiceUser(executableURL: executableURL) ?? ""

        if config.buildFromSource {
            let gitMarker = installDirectory.appendingPathComponent(".git")
            if !FileManager.default.fileExists(atPath: gitMarker.path) {
                throw Host.Error.invalidValue(
                    "installation",
                    "Configured for source build, but no .git repository found. Run 'deployerctl setup' to repair."
                )
            }
        }

        let serviceManager = try config.serviceBackend.makeManager(serviceUser: serviceUser)
        let updateContext = UpdateContext(
            application: context.application,
            config: config,
            serviceManager: serviceManager,
            serviceUser: serviceUser,
            installDirectory: installDirectory,
            executableName: executableName,
            serviceName: "deployer"
        )

        var stepTypes: [any UpdateStep.Type] = []
        if updateContext.isSourceInstall {
            stepTypes.append(SourceUpdateStep.self)
        } else {
            stepTypes.append(DownloadStep.self)
            stepTypes.append(StageBinaryStep.self)
        }
        stepTypes += [
            StopServiceStep.self,
            ActivateReleaseStep.self,
            PersistVersionStep.self,
            StartServiceStep.self,
            RefreshDeployerctlStep.self,
            UpdateSummaryStep.self,
        ]

        let steps = stepTypes.map { $0.init(context: updateContext, console: context.console) }

        printBanner(console: context.console)

        for (index, step) in steps.enumerated() {
            if updateContext.isUpToDate { break }

            context.console.stepHeader(title: step.title, index: index + 1, total: steps.count, color: .yellow)
            
            do {
                try await step.run()
            } catch {
                if step is ActivateReleaseStep || step is PersistVersionStep || step is StartServiceStep {
                    context.console.print("Update failed after service stop. Attempting rollback.")
                    try await UpdateRollback(context: updateContext).run(originalError: error)
                }
                throw error
            }
        }
    }

}

extension UpdateCommand {

    // See `ControlPreflight.query` and `docs/adr/0005-cli-server-state-channel.md`.
    private func preflightControlQuery(app: Application, config: Configuration, installDirectory: URL, console: any Console) async throws {
        switch await ControlPreflight.query(app: app, port: config.port, installDirectory: installDirectory) {
            case .ready: return
            case .busy(let phase): throw Error.serverBusy(phase)
            case .unhealthy(let reason): throw Error.serverUnhealthy(reason)
            case .unreachable(let reason):
                console.print("Warning: deployer server not reachable for state check (\(reason)). Proceeding; flock still enforces update mutual exclusion.")
        }
    }

}

extension UpdateCommand {

    private func printBanner(console: any Console) {
        console.newLine()
        console.ruler(color: .yellow)
        console.output("  Vapor Deployer · Update".consoleText(color: .yellow, isBold: true))
        console.ruler(color: .yellow)
        console.newLine()
        console.output("  Updates the deployer from release assets or source checkout.")
        console.output("  Automatically restarts the service after staging new assets.")
        console.newLine()
    }

}
