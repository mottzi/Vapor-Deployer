import Foundation

enum SystemFileSystem {

    /// Writes via a temp file and installs with explicit mode/ownership to avoid partial writes and wrong permissions.
    static func writeFile(
        _ contents: String,
        to path: String,
        mode: String = "0644",
        owner: String = "root",
        group: String = "root"
    ) async throws {

        let temporaryURL = FileManager.default.temporaryDirectory.appendingPathComponent("deployer-\(UUID().uuidString)")
        try contents.write(to: temporaryURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        try await Shell.runThrowing("install", ["-m", mode, "-o", owner, "-g", group, temporaryURL.path, path])
    }

    /// Creates or normalizes a directory with explicit ownership so reruns converge without manual `mkdir/chown` sequencing.
    static func installDirectory(
        _ path: String,
        mode: String = "0755",
        owner: String,
        group: String
    ) async throws {
        try await Shell.runThrowing("install", ["-d", "-m", mode, "-o", owner, "-g", group, path])
    }

    /// Deletes a managed path only when present to keep cleanup idempotent across reruns.
    static func removeIfPresent(_ path: String) throws {
        guard FileManager.default.fileExists(atPath: path) else { return }
        try FileManager.default.removeItem(atPath: path)
    }

    /// Replaces a destination by remove-then-copy so template or asset updates never merge with stale previous contents.
    static func copyReplacing(source: String, destination: String) throws {
        try removeIfPresent(destination)
        try FileManager.default.copyItem(atPath: source, toPath: destination)
    }

    /// A hidden path beside `destination` for staging: write the file (e.g. with `install(1)`), then
    /// `commitStagedBinary(from:to:)` to rename it into place.
    static func stagedInstallTmpPath(for destination: String) -> String {
        let url = URL(fileURLWithPath: destination)
        return url
            .deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
            .path
    }

    /// Atomically moves `tmpPath` to `destination`. Tries `mv -f` if Foundation will not replace an existing file.
    /// Removes `tmpPath` only when both approaches fail.
    static func commitStagedBinary(from tmpPath: String, to destination: String) async throws {
        do {
            try FileManager.default.moveItem(atPath: tmpPath, toPath: destination)
        } catch {
            do {
                try await Shell.runThrowing("mv", ["-f", tmpPath, destination])
            } catch {
                try? FileManager.default.removeItem(atPath: tmpPath)
                throw error
            }
        }
    }

}
