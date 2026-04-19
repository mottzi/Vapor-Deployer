import Foundation

final class SetupContext: @unchecked Sendable {

    let deployerRepositoryURL = "https://github.com/mottzi/Vapor-Deployer.git"
    let deployerRepositoryBranch = "main"
    let appBranch = "main"
    let deployerBuildMode = "release"
    let appBuildMode = "release"
    let deploymentMode = DeploymentMode.manual

    var serviceUser = ""
    var serviceUserUID: Int?
    var appRepositoryURL = ""
    var githubOwner = ""
    var githubRepo = ""
    var appName = ""
    var deployerPort = 8081
    var appPort = 8080
    var panelRoute = "/deployer"
    var serviceManagerKind = ServiceManagerKind.systemd
    var buildFromSource = false

    var paths: SetupPaths?

    var productName = ""
    var executableProducts: [String] = []
    var panelPassword = ""
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
    var releaseVersion: String?

    var webhookURL: String {
        publicBaseURL + (paths?.webhookPath ?? "")
    }

    func requirePaths() throws -> SetupPaths {
        guard let paths else { throw SetupCommand.Error.missingValue("paths") }
        return paths
    }

    func requireServiceUserUID() async throws -> Int {
        if let serviceUserUID { return serviceUserUID }

        let raw = try await Shell.runThrowing(["id", "-u", serviceUser]).trimmed
        guard let uid = Int(raw) else {
            throw SetupCommand.Error.invalidValue("serviceUserUID", "could not parse uid '\(raw)'")
        }

        serviceUserUID = uid
        return uid
    }

}
