import Foundation

extension DeployerctlInstaller {

    /// Errors encountered during the process of updating the deployerctl wrappers.
    enum Error: DescribedError {

        /// The invocation of the deployerctl sudo helper failed with the specified output.
        case refreshFailed(String)

        var errorDescription: String? {
            switch self {
            case .refreshFailed(let output):
                let trimmed = output.trimmed
                guard !trimmed.isEmpty else { return "Failed to refresh deployerctl wrapper." }
                return "Failed to refresh deployerctl wrapper.\n\(trimmed)"
            }
        }

    }

}
