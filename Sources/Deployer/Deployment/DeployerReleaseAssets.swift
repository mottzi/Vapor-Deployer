import Foundation

struct DeployerReleaseAssetDirectories: Sendable {

    let publicDirectory: String
    let resourcesDirectory: String

}

enum DeployerReleaseAssets {

    static let repository = "mottzi/Vapor-Deployer"
    static let releaseTagEnvironmentKey = "DEPLOYER_RELEASE_TAG"

    static func sourceArchiveURL(repository: String = repository, tag: String) throws -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "?#")
        guard let encodedTag = tag.addingPercentEncoding(withAllowedCharacters: allowed) else {
            throw Error.invalidTag(tag)
        }
        return "https://github.com/\(repository)/archive/refs/tags/\(encodedTag).tar.gz"
    }

    static func localReleaseTag(in sourceDirectory: URL) -> String? {
        let environmentTag = ProcessInfo.processInfo.environment[releaseTagEnvironmentKey]?.trimmed
        if let environmentTag, !environmentTag.isEmpty { return environmentTag }

        let versionFile = sourceDirectory.appendingPathComponent(".version").path
        let fileTag = (try? String(contentsOfFile: versionFile, encoding: .utf8))?.trimmed
        if let fileTag, !fileTag.isEmpty { return fileTag }

        return nil
    }

    static func ensureAssets(
        in stagingDirectory: String,
        repository: String = repository,
        tag: String
    ) async throws -> DeployerReleaseAssetDirectories {

        if let bundled = findAssets(in: stagingDirectory) {
            return bundled
        }

        return try await downloadSourceAssets(repository: repository, tag: tag, into: stagingDirectory)
    }

    static func downloadSourceAssets(
        repository: String = repository,
        tag: String,
        into stagingDirectory: String
    ) async throws -> DeployerReleaseAssetDirectories {

        let archiveURL = try sourceArchiveURL(repository: repository, tag: tag)
        let archive = "\(stagingDirectory)/deployer-source-\(UUID().uuidString).tar.gz"
        let sourceDirectory = "\(stagingDirectory)/deployer-source-\(UUID().uuidString)"

        defer { try? FileManager.default.removeItem(atPath: archive) }
        try FileManager.default.createDirectory(atPath: sourceDirectory, withIntermediateDirectories: true)

        try await Shell.runThrowing(["curl", "--silent", "--show-error", "--fail", "--location", "-o", archive, archiveURL])
        try await Shell.runThrowing(["tar", "-xzf", archive, "-C", sourceDirectory, "--warning=no-unknown-keyword"])

        guard let assets = findAssets(in: sourceDirectory) else {
            throw Error.assetsNotFound(tag)
        }
        return assets
    }

    static func findAssets(in directory: String) -> DeployerReleaseAssetDirectories? {
        let root = URL(fileURLWithPath: directory, isDirectory: true)
        if let assets = assets(at: root) { return assets }

        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        for entry in entries {
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            if let assets = assets(at: entry) { return assets }
        }

        return nil
    }

    private static func assets(at root: URL) -> DeployerReleaseAssetDirectories? {
        let publicDirectory = root.appendingPathComponent("Public", isDirectory: true)
        let resourcesDirectory = root.appendingPathComponent("Resources", isDirectory: true)

        guard isDirectory(publicDirectory.path), isDirectory(resourcesDirectory.path) else {
            return nil
        }

        return DeployerReleaseAssetDirectories(
            publicDirectory: publicDirectory.path,
            resourcesDirectory: resourcesDirectory.path
        )
    }

    private static func isDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    enum Error: LocalizedError {

        case invalidTag(String)
        case assetsNotFound(String)

        var errorDescription: String? {
            switch self {
            case .invalidTag(let tag):
                "Cannot build a GitHub source archive URL for release tag '\(tag)'."
            case .assetsNotFound(let tag):
                "The GitHub source archive for release '\(tag)' did not contain Public/ and Resources/."
            }
        }

    }

}
