import Foundation

extension DeployerRelease {
    
    /// Finds release web assets whether the archive extracts directly or through a single repository-root directory.
    static func findAssets(in directory: String) -> AssetDirectories? {
        
        let root = URL(fileURLWithPath: directory, isDirectory: true)
        if let assets = assets(at: root) { return assets }
        
        let entries = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        
        guard let entries else { return nil }
        
        for entry in entries {
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            if let assets = assets(at: entry) { return assets }
        }
        
        return nil
    }
    
}

extension DeployerRelease {

    /// Treats Public/ and Resources/ as an indivisible asset pair so setup/update never install a partial web UI.
    private static func assets(at root: URL) -> AssetDirectories? {
        let publicDirectory = root.appendingPathComponent("Public", isDirectory: true)
        let resourcesDirectory = root.appendingPathComponent("Resources", isDirectory: true)

        guard isDirectory(publicDirectory.path), isDirectory(resourcesDirectory.path) else {
            return nil
        }

        return AssetDirectories(
            publicDirectory: publicDirectory.path,
            resourcesDirectory: resourcesDirectory.path
        )
    }

    /// Confirms directory identity without following the looser file-exists path used for ordinary files.
    private static func isDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

}
