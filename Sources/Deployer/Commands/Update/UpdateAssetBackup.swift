import Foundation

/// Captures which installed asset directories existed so rollback can restore absence as well as contents.
struct UpdateAssetBackup {

    static let directoryNames = ["Public", "Resources"]

    let root: URL
    let backedUpDirectoryNames: Set<String>

    func directory(named name: String) -> URL? {
        guard backedUpDirectoryNames.contains(name) else { return nil }
        return root.appendingPathComponent(name, isDirectory: true)
    }

}
