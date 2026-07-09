import Vapor

/// Stages the downloaded binary and creates a backup of current assets for rollback.
struct StageBinaryStep: UpdateStep {

    let context: UpdateContext
    let console: any Console

    let title = "Staging update"

    func run() async throws {

        guard context.releaseVersion != nil else { return }
        guard context.releaseVersion != context.currentVersion else { return }
        guard let stagingDir = context.stagingDir else { return }

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
        let stagedSourceExists = fileManager.fileExists(atPath: stagedSource.path)
        guard stagedSourceExists else { throw UpdateCommand.Error.binaryNotFound(stagedSource.path) }

        try Host.FileSystem.removeIfPresent(context.stagedBinaryURL.path)
        try fileManager.copyItem(at: stagedSource, to: context.stagedBinaryURL)
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: context.stagedBinaryURL.path
        )
    }

    /// Copies the current assets into the update staging area so rollback can restore them.
    private func backupInstalledAssets(in stagingDir: String) throws -> UpdateAssetBackup {
        
        let fileManager = FileManager.default
        
        let backupRoot = URL(fileURLWithPath: stagingDir, isDirectory: true)
            .appendingPathComponent("deployer-assets-backup-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: backupRoot, withIntermediateDirectories: true)

        let installDirectory = context.stagedBinaryURL.deletingLastPathComponent()

        var backedUpDirectoryNames = Set<String>()
        
        for name in UpdateAssetBackup.directoryNames {
            let source = installDirectory.appendingPathComponent(name, isDirectory: true)
            guard fileManager.fileExists(atPath: source.path) else { continue }

            let destination = backupRoot.appendingPathComponent(name, isDirectory: true)
            try fileManager.copyItem(at: source, to: destination)
            
            backedUpDirectoryNames.insert(name)
        }

        return UpdateAssetBackup(root: backupRoot, backedUpDirectoryNames: backedUpDirectoryNames)
    }

}
