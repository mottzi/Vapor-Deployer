import Vapor

/// Swaps the staged binary and assets into place.
struct ActivateReleaseStep: UpdateStep {

    let context: UpdateContext
    let console: any Console

    let title = "Activating release"

    func run() async throws {

        guard context.releaseVersion != context.currentVersion else { return }

        try activateCandidateBinary()
        
        if context.isSourceInstall { return }
        guard let assets = context.releaseAssets else { return }
        try copyReleaseAssets(assets)
    }

}

extension ActivateReleaseStep {

    /// Swaps the staged binary into place and preserves a rollback copy.
    private func activateCandidateBinary() throws {
        let fileManager = FileManager.default
        let executableURL = context.stagedBinaryURL.deletingPathExtension()

        try SystemFileSystem.removeIfPresent(context.backupBinaryURL.path)

        let liveBinaryExists = fileManager.fileExists(atPath: executableURL.path)
        guard liveBinaryExists else { throw UpdateCommand.Error.binaryNotFound(executableURL.path) }

        let stagedBinaryExists = fileManager.fileExists(atPath: context.stagedBinaryURL.path)
        guard stagedBinaryExists else { throw UpdateCommand.Error.binaryNotFound(context.stagedBinaryURL.path) }

        try fileManager.moveItem(at: executableURL, to: context.backupBinaryURL)

        do {
            try fileManager.moveItem(at: context.stagedBinaryURL, to: executableURL)
        } catch {
            try? restoreBackup(fileManager: fileManager)
            throw UpdateCommand.Error.binarySwapFailed(error.localizedDescription)
        }
    }

    /// Replaces Public/ and Resources/ wholesale from the release payload or matching source archive.
    private func copyReleaseAssets(_ assets: DeployerReleaseAssetDirectories) throws {
        let fileManager = FileManager.default
        let installDirectory = context.stagedBinaryURL.deletingLastPathComponent()
        let candidateRoot = installDirectory
            .appendingPathComponent(".deployer-assets-new-\(UUID().uuidString)", isDirectory: true)
        defer { try? SystemFileSystem.removeIfPresent(candidateRoot.path) }

        try fileManager.createDirectory(at: candidateRoot, withIntermediateDirectories: true)

        for (name, sourcePath) in [
            ("Public", assets.publicDirectory),
            ("Resources", assets.resourcesDirectory)
        ] {
            let source = URL(fileURLWithPath: sourcePath, isDirectory: true)
            let candidate = candidateRoot.appendingPathComponent(name, isDirectory: true)
            try fileManager.copyItem(at: source, to: candidate)
        }

        for name in ReleaseAssetBackup.directoryNames {
            let candidate = candidateRoot.appendingPathComponent(name, isDirectory: true)
            let destination = installDirectory.appendingPathComponent(name, isDirectory: true)
            try SystemFileSystem.removeIfPresent(destination.path)
            try fileManager.moveItem(at: candidate, to: destination)
        }
    }

    /// Reinstates the last known-good executable after a failed update attempt.
    private func restoreBackup(fileManager: FileManager) throws {
        let executableURL = context.stagedBinaryURL.deletingPathExtension()
        try UpdateCommand.restoreBackupBinary(context: context, fileManager: fileManager, executableURL: executableURL)
    }

}
