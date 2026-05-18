import Foundation

/// Runtime configuration for the single deployment target managed by the deployer.
struct TargetConfiguration: Codable, Sendable {

    let name: String
    let repositoryURL: String?
    let directory: String
    let buildMode: String
    let pusheventPath: String
    let deploymentMode: DeploymentMode
    let binaryBehaviour: BinaryBehaviour
    let appPort: Int
    let branch: String
    let testing: Bool

}

extension TargetConfiguration {

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
