import Foundation

extension DeployerRelease {

    /// Encodes tag names for GitHub's archive route so source-asset fallback works for nontrivial release labels.
    static func sourceArchiveURL(repository: String = repository, tag: String) throws -> String {
        
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "?#")
        
        let encodedTag = tag.addingPercentEncoding(withAllowedCharacters: allowed)
        guard let encodedTag else { throw Error.invalidTag(tag) }
        
        return "https://github.com/\(repository)/archive/refs/tags/\(encodedTag).tar.gz"
    }

    /// Queries the GitHub API to determine the appropriate asset download URL for the host machine.
    static func fetchLatestReleaseMetadata(repository: String = repository) async throws -> (tagName: String, downloadURL: String) {

        let apiURL = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")
        guard let apiURL else { throw Error.invalidAPIURL("https://api.github.com/repos/\(repository)/releases/latest") }

        let (data, _) = try await GitHub.API.request(url: apiURL)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tagName = json["tag_name"] as? String,
              let assets = json["assets"] as? [[String: Any]]
        else { throw Error.malformedReleaseResponse }

        let systemArchitecture = try await Shell.runThrowing("uname", ["-m"]).trimmed
        let preferredAssetFilename = "deployer-linux-\(systemArchitecture).tar.gz"
        let targetAssetNames = [preferredAssetFilename, "deployer.tar.gz"]
        let downloadURL = targetAssetNames.lazy
            .compactMap { name in assets.first(where: { ($0["name"] as? String) == name }) }
            .compactMap { $0["browser_download_url"] as? String }
            .first

        guard let downloadURL else { throw Error.assetNotFound(preferredAssetFilename) }

        return (tagName, downloadURL)
    }

}
