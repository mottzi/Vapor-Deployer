import Foundation

extension SetupCommand {

    enum Error: DescribedError {

        case notRoot
        case unsupportedOperatingSystem(String)
        case missingValue(String)
        case invalidValue(String, String)
        case fileOperationFailed(String, Swift.Error)
        case releaseAssetNotFound(String)
        case githubAPI(String)
        case certificateLineageNotFound(String, String)
        case serviceTimeout(String)

        var errorDescription: String? {
            switch self {
            case .notRoot:
                "This command requires privileges. Run as root or with sudo."

            case .unsupportedOperatingSystem(let id):
                "This installer currently supports Ubuntu only. Detected: \(id)."

            case .missingValue(let value):
                "Setup value '\(value)' has not been collected yet."

            case .invalidValue(let field, let reason):
                "Invalid setup value '\(field)': \(reason)"

            case .fileOperationFailed(let path, let error):
                "File operation failed for '\(path)': \(error.localizedDescription)"

            case .releaseAssetNotFound(let asset):
                "No deployer release archive '\(asset)' found in the latest GitHub release."

            case .githubAPI(let message):
                "GitHub API request failed: \(message)"

            case .certificateLineageNotFound(let primary, let alias):
                "Cannot locate a valid TLS certificate lineage for \(primary) + \(alias) under /etc/letsencrypt/live/."

            case .serviceTimeout(let service):
                "Service '\(service)' did not reach a running state before the timeout."
            }
        }

    }

}
