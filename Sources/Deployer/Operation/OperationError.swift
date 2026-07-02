import Foundation

/// Domain errors surfaced by deployment-row operations across panel and CLI entrypoints.
enum OperationError: DescribedError {

    case anotherOperationInProgress
    case lockFailed(String, String)
    case operationIDMissing
    case deploymentIDMissing
    case deploymentNotFound(String)
    case deploymentCannotBuild
    case deploymentCannotRunSavedBinary
    case deploymentCannotTest
    case liveDeploymentCannotBeDeleted
    case liveDeploymentBinaryCannotBeRemoved
    case savedBinaryAlreadyExists
    case savedBinaryMissing
    case testingSavedBinaryUnsupported
    case skipTestsRequiresConfirmation
    case unreachableSHA(String)
    case ambiguousSHA(String, [Deployment])

    var errorDescription: String? {
        switch self {
            case .anotherOperationInProgress: "Another deployer operation is already running. Wait for it to finish, then retry."
            case .lockFailed(let path, let reason): "Unable to acquire operation lock at '\(path)': \(reason)"
            case .operationIDMissing: "Operation ID is missing."
            case .deploymentIDMissing: "Deployment ID is missing."
            case .deploymentNotFound(let selector): "No deployment found for '\(selector)'."
            case .deploymentCannotBuild: "Deployment not found or can't be built."
            case .deploymentCannotRunSavedBinary: "Deployment not found or can't restore its binary."
            case .deploymentCannotTest: "Deployment not found or can't be tested."
            case .liveDeploymentCannotBeDeleted: "Cannot delete the active live deployment."
            case .liveDeploymentBinaryCannotBeRemoved: "Cannot remove the saved binary for the active live deployment."
            case .savedBinaryAlreadyExists: "This deployment already has a saved binary."
            case .savedBinaryMissing: "Saved binary not found on disk."
            case .testingSavedBinaryUnsupported: "This deployment already has a saved binary. Run 'deployerctl test <sha>' first, then run it without --testing."
            case .skipTestsRequiresConfirmation: "Skipping configured tests requires --yes."
            case .unreachableSHA(let selector): "Commit '\(selector)' could not be resolved from the configured branch."
            case .ambiguousSHA(let selector, let deployments): "Ambiguous SHA prefix '\(selector)'. Matching deployments:\n\(deployments.map { "\($0.shortSHA)  \($0.commitMessage)" }.joined(separator: "\n"))"
        }
    }

}
