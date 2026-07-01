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

        let operationLock = try OperationLock.acquire(installDirectory: installDirectory)
        defer { operationLock.release() }
        
        let updateLock = try UpdateLock.acquire(installDirectory: installDirectory)
        defer { updateLock.release() }

        let updateContext = UpdateContext(
            installDirectory: installDirectory,
            executableName: executableName,
            serviceName: "deployer"
        )
        
        updateContext.serviceUser = await ConfigDiscovery.resolveServiceUser(executableURL: executableURL) ?? ""
        updateContext.isSourceInstall = config.buildFromSource
        updateContext.deployerBranch = config.deployerBranch

        if updateContext.isSourceInstall {
            let gitMarker = installDirectory.appendingPathComponent(".git")
            if !FileManager.default.fileExists(atPath: gitMarker.path) {
                throw SystemError.invalidValue(
                    "installation",
                    "Configured for source build, but no .git repository found. Run 'deployerctl setup' to repair."
                )
            }
        }

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
                    try await rollback(context: updateContext, originalError: error)
                }
                throw error
            }
        }
    }

}

private extension UpdateCommand {

    // See `ControlPreflight.query` and `docs/adr/0005-cli-server-state-channel.md`.
    func preflightControlQuery(app: Application, config: Configuration, installDirectory: URL, console: any Console) async throws {
        switch await ControlPreflight.query(app: app, port: config.port, installDirectory: installDirectory) {
            case .ready: return
            case .busy(let phase): throw Error.serverBusy(phase)
            case .unhealthy(let reason): throw Error.serverUnhealthy(reason)
            case .unreachable(let reason):
                console.print("Warning: deployer server not reachable for state check (\(reason)). Proceeding; flock still enforces update mutual exclusion.")
        }
    }

}

private extension UpdateCommand {

    func printBanner(console: any Console) {
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

extension UpdateCommand {
    
    /// Restores the last known-good binary and requires the service manager to recover before declaring rollback success.
    private func rollback(context: UpdateContext, originalError: Swift.Error) async throws {
        let fileManager = FileManager.default
        let config = try Configuration.load()
        let manager = try config.serviceManager.makeManager(serviceUser: context.managerServiceUser)
        let executableURL = context.stagedBinaryURL.deletingPathExtension()
        
        do {
            let isRunning = await manager.isRunning(product: context.serviceName)
            if isRunning { try await manager.stop(product: context.serviceName) }
            
            var restoreError: Swift.Error?
            do {
                try Self.restoreBackupBinary(context: context, fileManager: fileManager, executableURL: executableURL)
            } catch {
                restoreError = error
            }
            
            do {
                if let assetBackup = context.assetBackup {
                    try restoreReleaseAssets(from: assetBackup, installDirectory: executableURL.deletingLastPathComponent(), fileManager: fileManager)
                }
            } catch {
                restoreError = restoreError ?? error
            }

            do {
                try restoreVersionMarkerIfNeeded(context: context, fileManager: fileManager)
            } catch {
                restoreError = restoreError ?? error
            }
            
            if let restoreError { throw restoreError }
            
            try await manager.start(product: context.serviceName)
            
            let rollbackStatus = await manager.waitForStableStatus(product: context.serviceName)
            guard rollbackStatus.isRunning else { throw Error.rollbackVerificationFailed(rollbackStatus.label) }
        } catch {
            throw Error.rollbackFailed(originalError.localizedDescription, error.localizedDescription)
        }
        
        throw Error.rollbackSucceeded(originalError.localizedDescription)
    }
    
}

extension UpdateCommand {
    
    /// Reinstates the last known-good executable after a failed update attempt.
    static func restoreBackupBinary(context: UpdateContext, fileManager: FileManager, executableURL: URL) throws {
        let backupBinaryExists = fileManager.fileExists(atPath: context.backupBinaryURL.path)
        guard backupBinaryExists else { throw Error.binaryNotFound(context.backupBinaryURL.path) }

        try SystemFileSystem.removeIfPresent(executableURL.path)
        try fileManager.moveItem(at: context.backupBinaryURL, to: executableURL)
    }

    /// Restores asset directories to the exact pre-update state captured by `backupInstalledAssets`.
    private func restoreReleaseAssets(from backup: ReleaseAssetBackup, installDirectory: URL, fileManager: FileManager) throws {
        for name in ReleaseAssetBackup.directoryNames {
            let destination = installDirectory.appendingPathComponent(name, isDirectory: true)
            try SystemFileSystem.removeIfPresent(destination.path)

            guard let source = backup.directory(named: name) else { continue }
            try fileManager.copyItem(at: source, to: destination)
        }
    }

    /// Restores the version marker captured before the candidate version was written.
    private func restoreVersionMarkerIfNeeded(context: UpdateContext, fileManager: FileManager) throws {
        guard context.versionMarkerAdvanced else { return }

        if context.previousVersionFileExisted {
            guard let data = context.previousVersionFileData else {
                throw Error.versionMarkerRollbackFailed(context.versionFileURL.path, "previous marker contents were not captured")
            }

            do {
                try data.write(to: context.versionFileURL, options: .atomic)
            } catch {
                throw Error.versionMarkerRollbackFailed(context.versionFileURL.path, error.localizedDescription)
            }

            return
        }

        do {
            if fileManager.fileExists(atPath: context.versionFileURL.path) {
                try fileManager.removeItem(at: context.versionFileURL)
            }
        } catch {
            throw Error.versionMarkerRollbackFailed(context.versionFileURL.path, error.localizedDescription)
        }
    }

}

struct ReleaseAssetBackup: Sendable {

    static let directoryNames = ["Public", "Resources"]

    let root: URL
    let backedUpDirectoryNames: Set<String>

    func directory(named name: String) -> URL? {
        guard backedUpDirectoryNames.contains(name) else { return nil }
        return root.appendingPathComponent(name, isDirectory: true)
    }

}
