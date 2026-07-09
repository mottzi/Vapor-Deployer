import Vapor

/// Owns the immutable dependencies and evolving state shared by one update transaction.
final class UpdateContext {

    let application: Application
    let config: Configuration
    let serviceManager: any ServiceManager
    let serviceUser: String
    let installDirectory: URL

    let stagedBinaryURL: URL
    let backupBinaryURL: URL
    let versionFileURL: URL
    let serviceName: String

    var releaseVersion: String?
    var downloadURL: String?
    var stagingDir: String?
    var releaseAssets: DeployerRelease.AssetDirectories?
    var assetBackup: UpdateAssetBackup?
    var currentVersion: String?
    var previousVersionFileExisted = false
    var previousVersionFileData: Data?
    var versionMarkerAdvanced = false
    var isUpToDate = false

    var deployerBranch: String { config.deployerBranch }
    var isSourceInstall: Bool { config.buildFromSource }

    init(
        application: Application,
        config: Configuration,
        serviceManager: any ServiceManager,
        serviceUser: String,
        installDirectory: URL,
        executableName: String,
        serviceName: String
    ) {
        self.application = application
        self.config = config
        self.serviceManager = serviceManager
        self.serviceUser = serviceUser
        self.installDirectory = installDirectory
        self.stagedBinaryURL = installDirectory.appendingPathComponent("\(executableName).new")
        self.backupBinaryURL = installDirectory.appendingPathComponent("\(executableName).old")
        self.versionFileURL = installDirectory.appendingPathComponent(".version")
        self.serviceName = serviceName
    }

}
