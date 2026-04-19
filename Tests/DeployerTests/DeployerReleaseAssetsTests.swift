import XCTest
@testable import deployer

final class DeployerReleaseAssetsTests: XCTestCase {

    func testFindAssetsAtArchiveRoot() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try makeAssetDirectories(at: root)

        let assets = try XCTUnwrap(DeployerReleaseAssets.findAssets(in: root.path))
        XCTAssertEqual(normalize(assets.publicDirectory), normalize(root.appendingPathComponent("Public").path))
        XCTAssertEqual(normalize(assets.resourcesDirectory), normalize(root.appendingPathComponent("Resources").path))
    }

    func testFindAssetsOneDirectoryBelowArchiveRoot() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceRoot = root.appendingPathComponent("Vapor-Deployer-0.12.0", isDirectory: true)
        try makeAssetDirectories(at: sourceRoot)

        let assets = try XCTUnwrap(DeployerReleaseAssets.findAssets(in: root.path))
        XCTAssertEqual(normalize(assets.publicDirectory), normalize(sourceRoot.appendingPathComponent("Public").path))
        XCTAssertEqual(normalize(assets.resourcesDirectory), normalize(sourceRoot.appendingPathComponent("Resources").path))
    }

    func testSourceArchiveURLUsesReleaseTag() throws {
        let url = try DeployerReleaseAssets.sourceArchiveURL(tag: "0.12.0")
        XCTAssertEqual(url, "https://github.com/mottzi/Vapor-Deployer/archive/refs/tags/0.12.0.tar.gz")
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("deployer-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeAssetDirectories(at root: URL) throws {
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Public", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Resources", isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    private func normalize(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

}
