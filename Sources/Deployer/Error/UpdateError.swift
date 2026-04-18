import Foundation

extension UpdateCommand {

    enum Error: DescribedError {

        case invalidExecutablePath(String)
        case releaseAssetNotFound(String)
        case binaryNotFound(String)
        case binarySwapFailed(String)
        case restartVerificationFailed(String)
        case rollbackVerificationFailed(String)
        case rollbackSucceeded(String)
        case rollbackFailed(String, String)

        var errorDescription: String? {
            switch self {
            case .invalidExecutablePath(let path):
                "Unable to determine deployer executable name from '\(path)'."

            case .releaseAssetNotFound(let asset):
                "No release archive '\(asset)' found in the latest GitHub release."

            case .binaryNotFound(let path):
                "Expected deployer binary not found at '\(path)'."

            case .binarySwapFailed(let error):
                "Failed to swap in the updated deployer binary: \(error)"

            case .restartVerificationFailed(let status):
                "The service manager did not report the deployer as running after update. Final status: \(status)."

            case .rollbackVerificationFailed(let status):
                "Rollback restart did not recover the deployer. Final status: \(status)."

            case .rollbackSucceeded(let error):
                "Update failed, but rollback restored the previous deployer binary. Original error: \(error)"

            case .rollbackFailed(let original, let rollback):
                "Update failed and rollback also failed.\nOriginal error: \(original)\nRollback error: \(rollback)"
            }
        }

    }

}
