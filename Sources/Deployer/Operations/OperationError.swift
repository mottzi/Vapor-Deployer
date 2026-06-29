import Foundation

/// Domain errors surfaced by deployment-row operations across panel and CLI entrypoints.
enum OperationError: DescribedError {

    case anotherOperationInProgress
    case lockFailed(String, String)
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
    case ambiguousSHA(String, [Deployment])
    case unreachableSHA(String)

    var errorDescription: String? {
        switch self {
        case .anotherOperationInProgress:
            return "Another deployer operation is already running. Wait for it to finish, then retry."

        case .lockFailed(let path, let reason):
            return "Unable to acquire operation lock at '\(path)': \(reason)"

        case .deploymentIDMissing:
            return "Deployment ID is missing."

        case .deploymentNotFound(let selector):
            return "No deployment found for '\(selector)'."

        case .deploymentCannotBuild:
            return "Deployment not found or can't be built."

        case .deploymentCannotRunSavedBinary:
            return "Deployment not found or can't restore its binary."

        case .deploymentCannotTest:
            return "Deployment not found or can't be tested."

        case .liveDeploymentCannotBeDeleted:
            return "Cannot delete the active live deployment."

        case .liveDeploymentBinaryCannotBeRemoved:
            return "Cannot remove the saved binary for the active live deployment."

        case .savedBinaryAlreadyExists:
            return "This deployment already has a saved binary."

        case .savedBinaryMissing:
            return "Saved binary not found on disk."

        case .testingSavedBinaryUnsupported:
            return "This deployment already has a saved binary. Run 'deployerctl test <sha>' first, then run it without --testing."

        case .skipTestsRequiresConfirmation:
            return "Skipping configured tests requires --yes."

        case .ambiguousSHA(let selector, let deployments):
            let matches = deployments
                .map { "\($0.shortSHA)  \($0.commitMessage)" }
                .joined(separator: "\n")
            return "Ambiguous SHA prefix '\(selector)'. Matching deployments:\n\(matches)"

        case .unreachableSHA(let selector):
            return "Commit '\(selector)' could not be resolved from the configured branch."
        }
    }

}
