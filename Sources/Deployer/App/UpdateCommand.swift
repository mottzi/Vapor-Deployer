import Vapor
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Performs an in-place update of the deployed installation by downloading the latest GitHub release.
struct UpdateCommand: AsyncCommand {

    struct Signature: CommandSignature {}

    var help: String { "Updates the deployer installation." }

    /// Downloads the latest release, extracts it, and does a stop / swap / start with rollback on failure.
    func run(using context: CommandContext, signature: Signature) async throws {

        let console = context.console
        let paths = try Paths.resolve()
        let config = try Configuration.load()
        let manager = config.serviceManager.makeManager()

        console.print("Checking for deployer updates.")

        let (tagName, downloadURL) = try await fetchLatestRelease()

        let currentVersion = readInstalledVersion(at: paths.versionFileURL)
        guard tagName != currentVersion else {
            console.print("Deployer is already up to date (\(tagName)).")
            return
        }

        if let current = currentVersion {
            console.print("Updating deployer from \(current) to \(tagName).")
        } else {
            console.print("Updating deployer to \(tagName).")
        }

        let tmpArchive = try await Shell.runThrowing("mktemp").trimmed
        defer { try? FileManager.default.removeItem(atPath: tmpArchive) }

        let stagingDir = try await Shell.runThrowing("mktemp -d").trimmed
        defer { try? FileManager.default.removeItem(atPath: stagingDir) }

        console.print("Downloading release.")
        try await Shell.runThrowing("curl --silent --show-error --fail --location -o '\(tmpArchive)' '\(downloadURL)'")

        console.print("Extracting release archive.")
        try await Shell.runThrowing("tar -xzf '\(tmpArchive)' -C '\(stagingDir)' --warning=no-unknown-keyword 2>/dev/null")

        try stageCandidateBinary(from: stagingDir, using: paths)

        console.print("Stopping service '\(paths.serviceName)'.")
        let wasRunning = await manager.isRunning(product: paths.serviceName)
        if wasRunning { try await manager.stop(product: paths.serviceName) }

        do {
            try activateCandidateBinary(using: paths)
            try copyReleaseAssets(from: stagingDir, using: paths)

            console.print("Starting service '\(paths.serviceName)'.")
            try await manager.start(product: paths.serviceName)

            let finalStatus = await waitForStableStatus(of: paths.serviceName, manager: manager)
            guard finalStatus.isRunning else { throw Error.restartVerificationFailed(finalStatus.label) }

            writeInstalledVersion(tagName, at: paths.versionFileURL)
            console.print("Deployer update to \(tagName) completed successfully.")
        } catch {
            console.print("Update failed after service stop. Attempting rollback.")
            try await rollback(using: paths, manager: manager, originalError: error)
        }
    }

}

extension UpdateCommand {

    /// Hits the GitHub releases API and returns the latest tag name and the best-matching archive download URL.
    func fetchLatestRelease() async throws -> (tagName: String, downloadURL: String) {
        guard let apiURL = URL(string: "https://api.github.com/repos/mottzi/Vapor-Deployer/releases/latest") else {
            throw Error.releaseAssetNotFound("invalid API URL")
        }

        var request = URLRequest(url: apiURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tagName = json["tag_name"] as? String,
              let assets = json["assets"] as? [[String: Any]] else {
            throw Error.releaseAssetNotFound("malformed release response")
        }

        let arch = try await Shell.runThrowing("uname -m").trimmed
        let preferredAsset = "deployer-linux-\(arch).tar.gz"

        let downloadURL = assets
            .first(where: { ($0["name"] as? String) == preferredAsset })
            .flatMap { $0["browser_download_url"] as? String }
            ?? assets
            .first(where: { ($0["name"] as? String) == "deployer.tar.gz" })
            .flatMap { $0["browser_download_url"] as? String }

        guard let downloadURL else {
            throw Error.releaseAssetNotFound(preferredAsset)
        }

        return (tagName, downloadURL)
    }

    /// Returns the release tag recorded in the install directory, or nil if no version file exists.
    func readInstalledVersion(at url: URL) -> String? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let trimmed = content.trimmed
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Persists the installed release tag so future update checks can skip unchanged releases.
    func writeInstalledVersion(_ version: String, at url: URL) {
        try? version.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Copies the binary from the staging directory beside the live one so cutover only happens after a successful extraction.
    func stageCandidateBinary(from stagingDir: String, using paths: Paths) throws {
        let fileManager = FileManager.default
        let executableName = paths.executableURL.lastPathComponent
        let stagedSource = URL(fileURLWithPath: stagingDir).appendingPathComponent(executableName)

        guard fileManager.fileExists(atPath: stagedSource.path) else {
            throw Error.binaryNotFound(stagedSource.path)
        }

        try removeIfPresent(paths.stagedBinaryURL, fileManager: fileManager)
        try fileManager.copyItem(at: stagedSource, to: paths.stagedBinaryURL)
        try fileManager.setAttributes([.posixPermissions: NSNumber(value: Int16(0o755))], ofItemAtPath: paths.stagedBinaryURL.path)
    }

    /// Swaps the staged binary into place and preserves a rollback copy.
    func activateCandidateBinary(using paths: Paths) throws {
        let fileManager = FileManager.default

        try removeIfPresent(paths.backupBinaryURL, fileManager: fileManager)

        let liveBinaryExists = fileManager.fileExists(atPath: paths.executableURL.path)
        guard liveBinaryExists else { throw Error.binaryNotFound(paths.executableURL.path) }

        let stagedBinaryExists = fileManager.fileExists(atPath: paths.stagedBinaryURL.path)
        guard stagedBinaryExists else { throw Error.binaryNotFound(paths.stagedBinaryURL.path) }

        try fileManager.moveItem(at: paths.executableURL, to: paths.backupBinaryURL)

        do {
            try fileManager.moveItem(at: paths.stagedBinaryURL, to: paths.executableURL)
        } catch {
            try? restoreBackup(using: paths, fileManager: fileManager)
            throw Error.binarySwapFailed(error.localizedDescription)
        }
    }

    /// Replaces Public/ and Resources/ wholesale from the staging area.
    func copyReleaseAssets(from stagingDir: String, using paths: Paths) throws {
        let stagingURL = URL(fileURLWithPath: stagingDir, isDirectory: true)
        let fileManager = FileManager.default

        for directory in ["Public", "Resources"] {
            let source = stagingURL.appendingPathComponent(directory, isDirectory: true)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            let dest = paths.installDirectory.appendingPathComponent(directory, isDirectory: true)
            try removeIfPresent(dest, fileManager: fileManager)
            try fileManager.copyItem(at: source, to: dest)
        }
    }

    /// Restores the last known-good binary and requires the service manager to recover before declaring rollback success.
    func rollback(using paths: Paths, manager: any ServiceManager, originalError: Swift.Error) async throws {
        let fileManager = FileManager.default

        do {
            let isRunning = await manager.isRunning(product: paths.serviceName)
            if isRunning { try await manager.stop(product: paths.serviceName) }

            try restoreBackup(using: paths, fileManager: fileManager)
            try await manager.start(product: paths.serviceName)

            let rollbackStatus = await waitForStableStatus(of: paths.serviceName, manager: manager)
            guard rollbackStatus.isRunning else { throw Error.rollbackVerificationFailed(rollbackStatus.label) }
        } catch {
            throw Error.rollbackFailed(originalError.localizedDescription, error.localizedDescription)
        }

        throw Error.rollbackSucceeded(originalError.localizedDescription)
    }

    /// Waits through transient service states so the command judges the final service state instead of a race.
    func waitForStableStatus(of serviceName: String, manager: any ServiceManager) async -> ServiceStatus {
        for _ in 0..<10 {
            let status = await manager.status(product: serviceName)
            let isStableStatus = status.isRunning || !status.isTransitioning
            if isStableStatus { return status }

            try? await Task.sleep(for: .milliseconds(500))
        }

        return await manager.status(product: serviceName)
    }

    /// Reinstates the last known-good executable after a failed update attempt.
    func restoreBackup(using paths: Paths, fileManager: FileManager) throws {
        let backupBinaryExists = fileManager.fileExists(atPath: paths.backupBinaryURL.path)
        guard backupBinaryExists else { throw Error.binaryNotFound(paths.backupBinaryURL.path) }

        try removeIfPresent(paths.executableURL, fileManager: fileManager)
        try fileManager.moveItem(at: paths.backupBinaryURL, to: paths.executableURL)
    }

    /// Removes stale artifacts from earlier attempts so each update starts from a predictable filesystem state.
    func removeIfPresent(_ url: URL, fileManager: FileManager) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

}

extension UpdateCommand {

    /// Captures install-local paths so the command always targets the launched deployer installation.
    struct Paths: Sendable {

        let executableURL: URL
        let installDirectory: URL
        let stagedBinaryURL: URL
        let backupBinaryURL: URL
        let versionFileURL: URL
        let serviceName: String

        /// Resolves update paths from the launched executable rather than the caller's current working directory.
        static func resolve(
            executableURL: URL? = nil,
            serviceName: String = "deployer"
        ) throws -> Paths {

            let executableURL = try executableURL ?? Configuration.getExecutableURL()
            let resolvedExecutableURL = executableURL.standardizedFileURL.resolvingSymlinksInPath()
            let installDirectory = resolvedExecutableURL.deletingLastPathComponent()
            let executableName = resolvedExecutableURL.lastPathComponent

            guard !executableName.isEmpty else { throw Error.invalidExecutablePath(resolvedExecutableURL.path) }

            return Paths(
                executableURL: resolvedExecutableURL,
                installDirectory: installDirectory,
                stagedBinaryURL: installDirectory.appendingPathComponent("\(executableName).new"),
                backupBinaryURL: installDirectory.appendingPathComponent("\(executableName).old"),
                versionFileURL: installDirectory.appendingPathComponent(".version"),
                serviceName: serviceName
            )
        }

    }

}
