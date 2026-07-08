import Foundation

extension DeployerRelease {

    /// Materializes the release archive into update/setup staging so callers can swap files only after extraction succeeds.
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

    /// Recovers Public/ and Resources/ from the tagged source archive when binary packaging cannot provide them locally.
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

        guard let assets = findAssets(in: sourceDirectory) else { throw Error.assetsNotFound(tag) }
        
        return assets
    }

}

extension DeployerRelease {

    /// Keeps binary releases usable even when the archive lacks web assets by falling back to the matching source tag.
    private static func ensureAssets(
        in stagingDirectory: String,
        repository: String = repository,
        tag: String
    ) async throws -> AssetDirectories {

        if let bundled = findAssets(in: stagingDirectory) { return bundled }
        
        return try await downloadSourceAssets(repository: repository, tag: tag, into: stagingDirectory)
    }

    /// Encodes tag names for GitHub's archive route so source-asset fallback works for nontrivial release labels.
    private static func sourceArchiveURL(repository: String = repository, tag: String) throws -> String {
        
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "?#")
        
        let encodedTag = tag.addingPercentEncoding(withAllowedCharacters: allowed)
        guard let encodedTag else { throw Error.invalidTag(tag) }
        
        return "https://github.com/\(repository)/archive/refs/tags/\(encodedTag).tar.gz"
    }

    /// Finds release web assets whether the archive extracts directly or through a single repository-root directory.
    private static func findAssets(in directory: String) -> AssetDirectories? {
        
        let root = URL(fileURLWithPath: directory, isDirectory: true)
        if let assets = assetDirectories(at: root) { return assets }
        
        let entries = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        
        guard let entries else { return nil }
        
        for entry in entries {
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            if let assets = assetDirectories(at: entry) { return assets }
        }
        
        return nil
    }

    /// Treats Public/ and Resources/ as an indivisible asset pair so setup/update never install a partial web UI.
    private static func assetDirectories(at root: URL) -> AssetDirectories? {
        let publicDirectory = root.appendingPathComponent("Public", isDirectory: true)
        let resourcesDirectory = root.appendingPathComponent("Resources", isDirectory: true)

        guard Host.FileSystem.isDirectory(publicDirectory.path),
              Host.FileSystem.isDirectory(resourcesDirectory.path)
        else {
            return nil
        }

        return AssetDirectories(
            publicDirectory: publicDirectory.path,
            resourcesDirectory: resourcesDirectory.path
        )
    }

}
