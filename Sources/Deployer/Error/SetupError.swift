import Foundation

extension SetupCommand {

    enum Error: DescribedError {

        case fileOperationFailed(String, Swift.Error)
        case githubAPI(String)
        case certificateLineageNotFound(String, String)

        var errorDescription: String? {
            switch self {
            case .fileOperationFailed(let path, let error):
                "File operation failed for '\(path)': \(error.localizedDescription)"

            case .githubAPI(let message):
                "GitHub API request failed: \(message)"

            case .certificateLineageNotFound(let primary, let alias):
                "Cannot locate a valid TLS certificate lineage for \(primary) + \(alias) under /etc/letsencrypt/live/."
            }
        }

    }

}
