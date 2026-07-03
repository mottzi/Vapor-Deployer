import Vapor

/// Shared mutable state for one update run, holding the identity, paths, and metadata needed to update an installation.
final class UpdateContext {

    let application: Application
    let installDirectory: URL

    var serviceUser = ""
    var serviceUserUID: Int?

    var serviceBackend = ServiceBackend.systemd
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
    var previousVersionFileExisted = false
    var previousVersionFileData: Data?
    var versionMarkerAdvanced = false
    var isUpToDate = false
    var isSourceInstall = false

    var managerServiceUser: String? {
        let trimmed = serviceUser.trimmed
        return trimmed.isEmpty ? nil : trimmed
    }

    init(application: Application, installDirectory: URL, executableName: String, serviceName: String) {
        self.application = application
        self.installDirectory = installDirectory
        self.stagedBinaryURL = installDirectory.appendingPathComponent("\(executableName).new")
        self.backupBinaryURL = installDirectory.appendingPathComponent("\(executableName).old")
        self.versionFileURL = installDirectory.appendingPathComponent(".version")
        self.serviceName = serviceName
    }

}
