import Foundation

/// Shared mutable state for one update run, holding the identity, paths, and metadata needed to update an installation.
final class UpdateContext {

    var serviceUser = ""
    var serviceUserUID: Int?

    var serviceManagerKind = ServiceManagerKind.systemd
    var deployerBranch = ""

    let stagedBinaryURL: URL
    let backupBinaryURL: URL
    let versionFileURL: URL
    let serviceName: String

    var releaseVersion: String?
    var downloadURL: String?
    var stagingDir: String?
    var releaseAssets: DeployerReleaseAssetDirectories?
    var assetBackup: ReleaseAssetBackup?
    var currentVersion: String?
    var isUpToDate = false
    var isSourceInstall = false

    var managerServiceUser: String? {
        let trimmed = serviceUser.trimmed
        return trimmed.isEmpty ? nil : trimmed
    }

    init(installDirectory: URL, executableName: String, serviceName: String) {
        self.stagedBinaryURL = installDirectory.appendingPathComponent("\(executableName).new")
        self.backupBinaryURL = installDirectory.appendingPathComponent("\(executableName).old")
        self.versionFileURL = installDirectory.appendingPathComponent(".version")
        self.serviceName = serviceName
    }

}
