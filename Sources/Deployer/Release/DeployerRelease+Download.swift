import Foundation

extension DeployerRelease {

    static func localReleaseTag(in sourceDirectory: URL) -> String? {
        let environmentTag = ProcessInfo.processInfo.environment[releaseTagEnvironmentKey]?.trimmed
        if let environmentTag, !environmentTag.isEmpty { return environmentTag }

        let versionFile = sourceDirectory.appendingPathComponent(".version", isDirectory: false)
        return ConfigDiscovery.readTrimmedTextFile(at: versionFile)
    }

    static func ensureAssets(
        in stagingDirectory: String,
        repository: String = repository,
        tag: String
    ) async throws -> AssetDirectories {

        if let bundled = findAssets(in: stagingDirectory) {
            return bundled
        }

        return try await downloadSourceAssets(repository: repository, tag: tag, into: stagingDirectory)
    }

    static func downloadRelease(
        tag: String,
        downloadURL: String,
        into stagingDirectory: String,
        didDownloadArchive: (() -> Void)? = nil
    ) async throws -> Payload {

        let archivePath = try await Shell.runThrowing("mktemp").trimmed
        defer { try? FileManager.default.removeItem(atPath: archivePath) }

        try await Shell.runThrowing("curl", ["--silent", "--show-error", "--fail", "--location", "-o", archivePath, downloadURL])
        didDownloadArchive?()
        try await Shell.runThrowing("tar", ["-xzf", archivePath, "-C", stagingDirectory, "--warning=no-unknown-keyword"])

        return Payload(
            binaryPath: "\(stagingDirectory)/deployer",
            assets: try await ensureAssets(in: stagingDirectory, tag: tag)
        )
    }

    static func downloadSourceAssets(
        repository: String = repository,
        tag: String,
        into stagingDirectory: String
    ) async throws -> AssetDirectories {

        let archiveURL = try sourceArchiveURL(repository: repository, tag: tag)
        let archive = "\(stagingDirectory)/deployer-source-\(UUID().uuidString).tar.gz"
        let sourceDirectory = "\(stagingDirectory)/deployer-source-\(UUID().uuidString)"

        defer { try? FileManager.default.removeItem(atPath: archive) }
        try FileManager.default.createDirectory(atPath: sourceDirectory, withIntermediateDirectories: true)

        try await Shell.runThrowing("curl", ["--silent", "--show-error", "--fail", "--location", "-o", archive, archiveURL])
        try await Shell.runThrowing("tar", ["-xzf", archive, "-C", sourceDirectory, "--warning=no-unknown-keyword"])

        guard let assets = findAssets(in: sourceDirectory) else {
            throw Error.assetsNotFound(tag)
        }
        return assets
    }

}
