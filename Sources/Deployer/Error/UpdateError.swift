import Foundation

extension UpdateCommand {

    enum Error: DescribedError {

        case invalidExecutablePath(String)
        case binaryNotFound(String)
        case binarySwapFailed(String)
        case restartVerificationFailed(String)
        case rollbackVerificationFailed(String)
        case versionMarkerCaptureFailed(String, String)
        case versionMarkerRollbackFailed(String, String)
        case rollbackSucceeded(String)
        case rollbackFailed(String, String)
        case anotherUpdateInProgress
        case lockFailed(String, String)
        case serverBusy(String)
        case serverUnhealthy(String)

        var errorDescription: String? {
            switch self {
            case .invalidExecutablePath(let path):
                "Unable to determine deployer executable name from '\(path)'."

            case .binaryNotFound(let path):
                "Expected deployer binary not found at '\(path)'."

            case .binarySwapFailed(let error):
                "Failed to swap in the updated deployer binary: \(error)"

            case .restartVerificationFailed(let status):
                "The service manager did not report the deployer as running after update. Final status: \(status)."

            case .rollbackVerificationFailed(let status):
                "Rollback restart did not recover the deployer. Final status: \(status)."

            case .versionMarkerCaptureFailed(let path, let reason):
                "Failed to capture deployer version marker at '\(path)' before update: \(reason)"

            case .versionMarkerRollbackFailed(let path, let reason):
                "Failed to restore deployer version marker at '\(path)': \(reason)"

            case .rollbackSucceeded(let error):
                "Update failed, but rollback restored the previous deployer binary. Original error: \(error)"

            case .rollbackFailed(let original, let rollback):
                "Update failed and rollback also failed.\nOriginal error: \(original)\nRollback error: \(rollback)"

            case .anotherUpdateInProgress:
                "Another deployer update is already running. Wait for it to finish, then retry."

            case .lockFailed(let path, let reason):
                "Unable to acquire update lock at '\(path)': \(reason)"

            case .serverBusy(let phase):
                "Deployer is busy (phase: \(phase)). Wait for the current operation to finish, then retry."

            case .serverUnhealthy(let reason):
                "Could not confirm the deployer is ready to be updated: \(reason). Stop the deployer service and retry to force the update."
            }
        }

    }

}
