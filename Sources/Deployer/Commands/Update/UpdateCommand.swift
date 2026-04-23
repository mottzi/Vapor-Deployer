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

        let executableURL = try Configuration.getExecutableURL()
        let resolvedExecutableURL = executableURL.standardizedFileURL.resolvingSymlinksInPath()
        let installDirectory = resolvedExecutableURL.deletingLastPathComponent()
        let executableName = resolvedExecutableURL.lastPathComponent

        guard !executableName.isEmpty else { throw Error.invalidExecutablePath(resolvedExecutableURL.path) }

        let updateContext = UpdateContext(
            installDirectory: installDirectory,
            executableName: executableName,
            serviceName: "deployer"
        )
        
        updateContext.serviceUser = await resolveServiceUser(executableURL: resolvedExecutableURL) ?? ""

        let stepTypes: [any UpdateStep.Type] = [
            DownloadStep.self,
            StageBinaryStep.self,
            StopServiceStep.self,
            ActivateReleaseStep.self,
            StartServiceStep.self,
            UpdateSummaryStep.self,
        ]

        let steps = stepTypes.map { $0.init(context: updateContext, console: context.console) }

        context.console.updateBanner()

        for (index, step) in steps.enumerated() {
            if updateContext.isUpToDate { break }

            step.printHeader(index: index + 1, total: steps.count)
            
            do {
                try await step.run()
            } catch {
                if step is ActivateReleaseStep || step is StartServiceStep {
                    context.console.print("Update failed after service stop. Attempting rollback.")
                    try await rollback(context: updateContext, originalError: error)
                }
                throw error
            }
        }
    }

}

extension UpdateCommand {
    
    /// Restores the last known-good binary and requires the service manager to recover before declaring rollback success.
    private func rollback(context: UpdateContext, originalError: Swift.Error) async throws {
        let fileManager = FileManager.default
        let config = try Configuration.load()
        let manager = config.serviceManager.makeManager(serviceUser: context.managerServiceUser)
        let executableURL = context.stagedBinaryURL.deletingPathExtension()
        
        do {
            let isRunning = await manager.isRunning(product: context.serviceName)
            if isRunning { try await manager.stop(product: context.serviceName) }
            
            var restoreError: Swift.Error?
            do {
                try restoreBackup(context: context, fileManager: fileManager, executableURL: executableURL)
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
            
            if let restoreError { throw restoreError }
            
            try await manager.start(product: context.serviceName)
            
            let rollbackStatus = await waitForStableStatus(of: context.serviceName, manager: manager)
            guard rollbackStatus.isRunning else { throw Error.rollbackVerificationFailed(rollbackStatus.label) }
        } catch {
            throw Error.rollbackFailed(originalError.localizedDescription, error.localizedDescription)
        }
        
        throw Error.rollbackSucceeded(originalError.localizedDescription)
    }
    
}

extension UpdateCommand {

    /// Resolves the configured service user so systemd user operations can target the right user manager when invoked as root.
    private func resolveServiceUser(executableURL: URL) async -> String? {
        let metadata = await ConfigDiscovery.loadDeployerctl()
        if let discovered = metadata["SERVICE_USER"]?.trimmed, !discovered.isEmpty {
            return discovered
        }
        
        let attributes = try? FileManager.default.attributesOfItem(atPath: executableURL.path)
        if let owner = attributes?[.ownerAccountName] as? String {
            let trimmed = owner.trimmed
            if !trimmed.isEmpty { return trimmed }
        }
        
        return nil
    }
    
    /// Reinstates the last known-good executable after a failed update attempt.
    private func restoreBackup(context: UpdateContext, fileManager: FileManager, executableURL: URL) throws {
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

    /// Waits through transient service states so the command judges the final service state instead of a race.
    private func waitForStableStatus(of serviceName: String, manager: any ServiceManager) async -> ServiceStatus {
        for _ in 0..<10 {
            let status = await manager.status(product: serviceName)
            let isStableStatus = status.isRunning || !status.isTransitioning
            if isStableStatus { return status }

            try? await Task.sleep(for: .milliseconds(500))
        }

        return await manager.status(product: serviceName)
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
