import Foundation

/// Represents the deployer's own published release payload and the local files derived from it.
enum DeployerRelease {

    static let repository = "mottzi/Vapor-Deployer"
    static let releaseTagEnvironmentKey = "DEPLOYER_RELEASE_TAG"

    struct AssetDirectories {

        let publicDirectory: String
        let resourcesDirectory: String

    }

    struct Payload {

        let binaryPath: String
        let assets: AssetDirectories

    }

    enum Error: LocalizedError {

        case invalidTag(String)
        case assetsNotFound(String)
        case malformedReleaseResponse
        case assetNotFound(String)
        case invalidAPIURL(String)

        var errorDescription: String? {
            switch self {
            case .invalidTag(let tag):
                "Cannot build a GitHub source archive URL for release tag '\(tag)'."
            case .assetsNotFound(let tag):
                "The GitHub source archive for release '\(tag)' did not contain Public/ and Resources/."
            case .malformedReleaseResponse:
                "Received a malformed release response from the GitHub API."
            case .assetNotFound(let asset):
                "No release archive '\(asset)' found in the latest GitHub release."
            case .invalidAPIURL(let url):
                "Cannot build a GitHub API URL for '\(url)'."
            }
        }

    }

}
