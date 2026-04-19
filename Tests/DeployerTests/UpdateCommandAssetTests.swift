import XCTest
@testable import deployer

final class UpdateCommandAssetTests: XCTestCase {

    func testAssetCopyFailureLeavesLiveAssetsUntouchedBeforeSwap() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let paths = try makePaths(root: root)
        try write("old-public", to: paths.installDirectory.appendingPathComponent("Public/old.txt"))
        try write("old-resources", to: paths.installDirectory.appendingPathComponent("Resources/old.txt"))

        let sourceRoot = root.appendingPathComponent("source", isDirectory: true)
        try write("new-public", to: sourceRoot.appendingPathComponent("Public/new.txt"))

        XCTAssertThrowsError(try UpdateCommand().copyReleaseAssets(
            DeployerReleaseAssetDirectories(
                publicDirectory: sourceRoot.appendingPathComponent("Public").path,
                resourcesDirectory: sourceRoot.appendingPathComponent("Resources").path
            ),
            using: paths
        ))

        XCTAssertEqual(try read(paths.installDirectory.appendingPathComponent("Public/old.txt")), "old-public")
        XCTAssertEqual(try read(paths.installDirectory.appendingPathComponent("Resources/old.txt")), "old-resources")
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.installDirectory.appendingPathComponent("Public/new.txt").path))
    }

    func testAssetBackupRestoresPreviousAssetState() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let paths = try makePaths(root: root)
        try write("old-public", to: paths.installDirectory.appendingPathComponent("Public/old.txt"))
        try write("old-resources", to: paths.installDirectory.appendingPathComponent("Resources/old.txt"))

        let sourceRoot = root.appendingPathComponent("source", isDirectory: true)
        try write("new-public", to: sourceRoot.appendingPathComponent("Public/new.txt"))
        try write("new-resources", to: sourceRoot.appendingPathComponent("Resources/new.txt"))

        let command = UpdateCommand()
        let backup = try command.backupInstalledAssets(using: paths, in: root.path)
        try command.copyReleaseAssets(
            DeployerReleaseAssetDirectories(
                publicDirectory: sourceRoot.appendingPathComponent("Public").path,
                resourcesDirectory: sourceRoot.appendingPathComponent("Resources").path
            ),
            using: paths
        )

        XCTAssertEqual(try read(paths.installDirectory.appendingPathComponent("Public/new.txt")), "new-public")
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.installDirectory.appendingPathComponent("Public/old.txt").path))

        try command.restoreReleaseAssets(from: backup, using: paths, fileManager: .default)

        XCTAssertEqual(try read(paths.installDirectory.appendingPathComponent("Public/old.txt")), "old-public")
        XCTAssertEqual(try read(paths.installDirectory.appendingPathComponent("Resources/old.txt")), "old-resources")
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.installDirectory.appendingPathComponent("Public/new.txt").path))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("deployer-update-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makePaths(root: URL) throws -> UpdateCommand.Paths {
        let installDirectory = root.appendingPathComponent("install", isDirectory: true)
        try FileManager.default.createDirectory(at: installDirectory, withIntermediateDirectories: true)
        let executableURL = installDirectory.appendingPathComponent("deployer")
        try write("binary", to: executableURL)

        return UpdateCommand.Paths(
            executableURL: executableURL,
            installDirectory: installDirectory,
            stagedBinaryURL: installDirectory.appendingPathComponent("deployer.new"),
            backupBinaryURL: installDirectory.appendingPathComponent("deployer.old"),
            versionFileURL: installDirectory.appendingPathComponent(".version"),
            serviceName: "deployer"
        )
    }

    private func write(_ value: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try value.write(to: url, atomically: true, encoding: .utf8)
    }

    private func read(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

}
