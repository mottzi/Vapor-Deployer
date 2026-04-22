import Vapor
import Foundation

/// Stages the downloaded binary and creates a backup of current assets for rollback.
struct StageBinaryStep: UpdateStep {

    let context: UpdateContext
    let console: any Console

    let title = "Staging update"

    func run() async throws {

        guard let tagName = context.releaseVersion,
              context.releaseVersion != context.currentVersion,
              let stagingDir = context.stagingDir else {
            return // Up to date
        }

        try stageCandidateBinary(from: stagingDir)
        context.assetBackup = try backupInstalledAssets(in: stagingDir)
    }

}

extension StageBinaryStep {

    /// Copies the binary from the staging directory beside the live one so cutover only happens after a successful extraction.
    private func stageCandidateBinary(from stagingDir: String) throws {
        let fileManager = FileManager.default
        let executableName = context.stagedBinaryURL.deletingPathExtension().lastPathComponent
        let stagedSource = URL(fileURLWithPath: stagingDir).appendingPathComponent(executableName)

        guard fileManager.fileExists(atPath: stagedSource.path) else {
            throw UpdateCommand.Error.binaryNotFound(stagedSource.path)
        }

        try SystemFileSystem.removeIfPresent(context.stagedBinaryURL.path)
        try fileManager.copyItem(at: stagedSource, to: context.stagedBinaryURL)
        try fileManager.setAttributes([.posixPermissions: NSNumber(value: Int16(0o755))], ofItemAtPath: context.stagedBinaryURL.path)
    }

    /// Copies the current assets into the update staging area so rollback can restore them.
    private func backupInstalledAssets(in stagingDir: String) throws -> ReleaseAssetBackup {
        let fileManager = FileManager.default
        let backupRoot = URL(fileURLWithPath: stagingDir, isDirectory: true)
            .appendingPathComponent("deployer-assets-backup-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: backupRoot, withIntermediateDirectories: true)

        let installDirectory = context.stagedBinaryURL.deletingLastPathComponent()

        var backedUpDirectoryNames = Set<String>()
        for name in ReleaseAssetBackup.directoryNames {
            let source = installDirectory.appendingPathComponent(name, isDirectory: true)
            guard fileManager.fileExists(atPath: source.path) else { continue }

            let destination = backupRoot.appendingPathComponent(name, isDirectory: true)
            try fileManager.copyItem(at: source, to: destination)
            backedUpDirectoryNames.insert(name)
        }

        return ReleaseAssetBackup(root: backupRoot, backedUpDirectoryNames: backedUpDirectoryNames)
    }

}
