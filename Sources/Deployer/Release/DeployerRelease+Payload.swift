import Foundation

extension DeployerRelease {

    /// Carries the staged binary and web assets together so activation never treats them as unrelated artifacts.
    struct Payload {

        let binaryPath: String
        let assets: AssetDirectories

    }
    
    /// Names the two web asset roots that setup/update replace as a single release-owned unit.
    struct AssetDirectories {

        let publicDirectory: String
        let resourcesDirectory: String

    }
    
}
