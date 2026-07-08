import Foundation

/// Shared mutable state for one setup run, holding user input, discovered host facts, and derived values for later steps.
final class SetupContext: InstallationContext {

    let deployerRepositoryURL = DeployerVersion.repositoryWebPageURL + ".git"
    var deployerRepositoryBranch = "main"
    let appBranch = "main"
    let deployerBuildMode = "release"
    let appBuildMode = "release"
    var deploymentMode = DeploymentMode.manual
    var binaryBehaviour = BinaryBehaviour.setupDefault
    var testing = true

    var serviceUser = ""
    var serviceUserUID: Int?
    var appRepositoryURL = ""
    var appRepositoryWebURL = ""
    var githubOwner = ""
    var githubRepo = ""
    var appName = ""
    var deployerPort = 8081
    var appPort = 8080
    var panelRoute = "/deployer"
    var serviceBackend = ServiceBackend.systemd
    var buildFromSource = false
    var previousBuildFromSource: Bool?

    var paths: InstallationPaths?

    var productName = ""
    var executableProducts: [String] = []
    var panelPasswordHash = ""
    var webhookSecret = ""
    var publicBaseURL = ""
    var primaryDomain = ""
    var aliasDomain = ""
    var certName = ""
    var certLineageFound = false
    var currentCertLineageIsStaging = false
    var usingStagingCertificates = false
    var tlsContactEmail = ""
    var githubToken = ""
    var previousMetadata: [String: String]?
    var orphanedPrimaryDomain: String?
    var orphanedCertNameToDelete: String?
    var releaseVersion: String?
    var managedAppHealthFailures: [String] = []

    var webhookURL: String { publicBaseURL + (paths?.webhookPath ?? "") }

}
