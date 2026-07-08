import Foundation

/// Resolves the running deployer version from release metadata or source-control fallback.
enum DeployerVersion {

    /// Public GitHub project page (HTTPS, no `.git`); used for the panel wordmark and as the base of the clone URL in setup.
    static let repositoryWebPageURL = "https://github.com/mottzi/Vapor-Deployer"

    /// Fallback label used when no release, source-control, or bundle version can be discovered.
    private static let unknownVersion = "unknown"

    /// Environment override injected by release packaging so unpacked binaries preserve their exact tag.
    private static let releaseTagEnvironmentKey = "DEPLOYER_RELEASE_TAG"
    
    /// Determines the best available version string for the active deployer binary.
    static func current() async -> String {

        guard let executableURL = try? Configuration.getExecutableURL() else {
            return bundleVersion() ?? unknownVersion
        }

        let executableDirectory = executableURL.deletingLastPathComponent()

        if let releaseTag = releaseTag(in: executableDirectory) {
            return releaseTag
        }

        if let gitVersion = await readGitVersion(near: executableDirectory) {
            return gitVersion
        }

        return bundleVersion() ?? unknownVersion
    }
    
    /// Reads release identity from the environment or install-time marker for a concrete deployer payload directory.
    static func releaseTag(in directory: URL) -> String? {
        
        let environmentTag = ProcessInfo.processInfo.environment[releaseTagEnvironmentKey]?.trimmed
        if let environmentTag, !environmentTag.isEmpty { return environmentTag }

        return readVersionFile(in: directory)
    }

}

extension DeployerVersion {

    /// Reads the install-time release marker persisted by setup and update commands.
    private static func readVersionFile(in directory: URL) -> String? {
        let fileURL = directory.appendingPathComponent(".version", isDirectory: false)
        return ConfigDiscovery.readTrimmedTextFile(at: fileURL)
    }

    /// Falls back to source-control metadata when running from a development checkout.
    private static func readGitVersion(near directory: URL) async -> String? {
        
        guard let gitRoot = findGitRoot(startingAt: directory) else { return nil }

        let describe = await Shell.run("git", ["-C", gitRoot.path, "describe", "--tags", "--always", "--dirty", "--abbrev=7"])
        if describe.exitCode == 0 {
            let value = describe.output.trimmed
            if !value.isEmpty { return value }
        }

        let revision = await Shell.run("git", ["-C", gitRoot.path, "rev-parse", "--short=7", "HEAD"])
        if revision.exitCode == 0 {
            let value = revision.output.trimmed
            if !value.isEmpty { return value }
        }

        return nil
    }

    /// Walks parent directories to detect repository roots in source installs and local development runs.
    private static func findGitRoot(startingAt directory: URL) -> URL? {
        
        let fileManager = FileManager.default
        var cursor = directory.standardizedFileURL

        while true {
            if fileManager.fileExists(atPath: cursor.appendingPathComponent(".git", isDirectory: false).path) {
                return cursor
            }

            let parent = cursor.deletingLastPathComponent()
            if parent.path == cursor.path {
                break
            }
            
            cursor = parent
        }

        return nil
    }

    /// Returns bundle-provided version metadata when available (mainly for platform-specific packaging).
    private static func bundleVersion() -> String? {
        
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String
        if let short, !short.trimmed.isEmpty { return short.trimmed }

        let build = info?["CFBundleVersion"] as? String
        if let build, !build.trimmed.isEmpty { return build.trimmed }

        return nil
    }

}
