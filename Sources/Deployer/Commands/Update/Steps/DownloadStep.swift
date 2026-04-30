import Vapor

/// Fetches the latest release from GitHub and downloads the appropriate payload for the host.
struct DownloadStep: UpdateStep {

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

        let stagingDir = try await Shell.runThrowing("mktemp", ["-d"]).trimmed
        context.stagingDir = stagingDir

        console.print("Downloading release.")
        let payload = try await DeployerReleaseAssets.downloadRelease(
            tag: tagName,
            downloadURL: downloadURL,
            into: stagingDir
        ) {
            console.print("Extracting release archive.")
        }
        context.releaseAssets = payload.assets
    }

}

extension DownloadStep {

    /// Returns the release tag recorded in the install directory, or nil if no version file exists.
    private func readInstalledVersion(at url: URL) -> String? {
        ConfigDiscovery.readTrimmedTextFile(at: url)
    }

}
