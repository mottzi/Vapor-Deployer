import Foundation

/// Runtime configuration for the single deployment target managed by the deployer.
struct TargetConfiguration: Codable, Sendable {

    var name: String
    var repositoryURL: String?
    var directory: String
    var buildMode: String
    var pusheventPath: String
    var deploymentMode: DeploymentMode
    var binaryBehaviour: BinaryBehaviour
    var appPort: Int
    var branch: String
    var testing: Bool

}

extension TargetConfiguration {

    var logFilePath: String { "\(directory)/deploy/\(name).log" }

    /// Validates and normalizes decoded target values using the executable directory as the base path.
    func resolved(relativeTo baseDirectoryURL: URL) throws -> TargetConfiguration {
        
        guard appPort > 0 else {
            throw Configuration.Error.invalidField("target.appPort", "must be greater than 0")
        }
        
        return try TargetConfiguration(
            name: Configuration.trimmedValue(name, field: "target.name"),
            repositoryURL: repositoryURL?.trimmed,
            directory: Configuration.trimmedFileSystemPath(directory, field: "target.directory", relativeTo: baseDirectoryURL),
            buildMode: Configuration.trimmedValue(buildMode, field: "target.buildMode"),
            pusheventPath: Configuration.trimmedValue(pusheventPath, field: "target.pusheventPath"),
            deploymentMode: deploymentMode,
            binaryBehaviour: binaryBehaviour.validated(field: "target.binaryBehaviour"),
            appPort: appPort,
            branch: Configuration.trimmedValue(branch, field: "target.branch"),
            testing: testing
        )
    }

}
