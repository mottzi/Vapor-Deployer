import Vapor

/// Fetches the latest release from GitHub and downloads the appropriate payload for the host.
struct FetchAndDownloadReleaseStep: UpdateStep {

    let context: UpdateContext
    let console: any Console

    let title = "Downloading release"

    func run() async throws {

        console.print("Checking for deployer updates.")

        let (tagName, downloadURL) = try await DeployerReleaseAssets.fetchLatestReleaseMetadata()
        context.releaseVersion = tagName
        context.downloadURL = downloadURL

        let currentVersion = readInstalledVersion(at: context.versionFileURL)
        context.currentVersion = currentVersion

        if tagName == currentVersion {
            console.print("Deployer is already up to date (\(tagName)).")
            context.isUpToDate = true
            return
        }

        if let current = currentVersion {
            console.print("Updating deployer from \(current) to \(tagName).")
        } else {
            console.print("Updating deployer to \(tagName).")
        }

        let tmpArchive = try await Shell.runThrowing("mktemp").trimmed
        defer { try? FileManager.default.removeItem(atPath: tmpArchive) }

        let stagingDir = try await Shell.runThrowing("mktemp", ["-d"]).trimmed
        context.stagingDir = stagingDir

        console.print("Downloading release.")
        try await Shell.runThrowing("curl", ["--silent", "--show-error", "--fail", "--location", "-o", tmpArchive, downloadURL])

        console.print("Extracting release archive.")
        try await Shell.runThrowing("tar", ["-xzf", tmpArchive, "-C", stagingDir, "--warning=no-unknown-keyword"])

        context.releaseAssets = try await DeployerReleaseAssets.ensureAssets(in: stagingDir, tag: tagName)
    }

}

extension FetchAndDownloadReleaseStep {

    /// Returns the release tag recorded in the install directory, or nil if no version file exists.
    private func readInstalledVersion(at url: URL) -> String? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let trimmed = content.trimmed
        return trimmed.isEmpty ? nil : trimmed
    }

}
