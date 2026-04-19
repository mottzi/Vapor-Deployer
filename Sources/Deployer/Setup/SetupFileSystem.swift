import Foundation

enum SetupFileSystem {

    static func writeFile(
        _ contents: String,
        to path: String,
        mode: String = "0644",
        owner: String = "root",
        group: String = "root"
    ) async throws {

        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("deployer-\(UUID().uuidString)")
        try contents.write(to: temporaryURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        try await Shell.runThrowing(["install", "-m", mode, "-o", owner, "-g", group, temporaryURL.path, path])
    }

    static func installDirectory(
        _ path: String,
        mode: String = "0755",
        owner: String,
        group: String
    ) async throws {

        try await Shell.runThrowing(["install", "-d", "-m", mode, "-o", owner, "-g", group, path])
    }

    static func removeIfPresent(_ path: String) throws {
        guard FileManager.default.fileExists(atPath: path) else { return }
        try FileManager.default.removeItem(atPath: path)
    }

    static func copyReplacing(source: String, destination: String) throws {
        try removeIfPresent(destination)
        try FileManager.default.copyItem(atPath: source, toPath: destination)
    }

}
