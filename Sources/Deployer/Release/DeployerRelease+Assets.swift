import Foundation

extension DeployerRelease {

    static func findAssets(in directory: String) -> AssetDirectories? {
        let root = URL(fileURLWithPath: directory, isDirectory: true)
        if let assets = assets(at: root) { return assets }

        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        for entry in entries {
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            if let assets = assets(at: entry) { return assets }
        }

        return nil
    }

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

    private static func isDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

}
