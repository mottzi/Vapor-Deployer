import XCTest
@testable import deployer

final class SetupValidatorsTests: XCTestCase {

    func testSafeNameMatchesInstallerConstraints() {
        XCTAssertTrue(SetupValidator.isSafeName("mottzi"))
        XCTAssertTrue(SetupValidator.isSafeName("my-app_1.2"))
        XCTAssertFalse(SetupValidator.isSafeName(""))
        XCTAssertFalse(SetupValidator.isSafeName("my app"))
        XCTAssertFalse(SetupValidator.isSafeName("my/app"))
    }

    func testPortValidationRejectsOutOfRangeValues() {
        XCTAssertTrue(SetupValidator.isValidPort("1"))
        XCTAssertTrue(SetupValidator.isValidPort("8080"))
        XCTAssertTrue(SetupValidator.isValidPort("65535"))
        XCTAssertFalse(SetupValidator.isValidPort("0"))
        XCTAssertFalse(SetupValidator.isValidPort("65536"))
        XCTAssertFalse(SetupValidator.isValidPort("abc"))
    }

    func testEmailValidationCoversInstallerShape() {
        XCTAssertTrue(SetupValidator.isValidEmail("admin@example.com"))
        XCTAssertTrue(SetupValidator.isValidEmail("first.last+deploy@example.co.uk"))
        XCTAssertFalse(SetupValidator.isValidEmail("admin"))
        XCTAssertFalse(SetupValidator.isValidEmail("admin@example"))
        XCTAssertFalse(SetupValidator.isValidEmail("@example.com"))
    }

    func testPublicBaseURLRequiresHTTPSDomainWithoutPathOrPort() {
        XCTAssertTrue(SetupValidator.isValidPublicBaseURL("https://example.com"))
        XCTAssertTrue(SetupValidator.isValidPublicBaseURL("https://www.example.com/"))
        XCTAssertFalse(SetupValidator.isValidPublicBaseURL("http://example.com"))
        XCTAssertFalse(SetupValidator.isValidPublicBaseURL("https://example.com:8443"))
        XCTAssertFalse(SetupValidator.isValidPublicBaseURL("https://example.com/path"))
        XCTAssertFalse(SetupValidator.isValidPublicBaseURL("https://localhost"))
    }

    func testGitHubSSHURLParsingNormalizesRepositorySuffix() throws {
        let parsed = try XCTUnwrap(SetupValidator.parseGitHubSSHURL("git@github.com:mottzi/Vapor-Deployer.git"))
        XCTAssertEqual(parsed.owner, "mottzi")
        XCTAssertEqual(parsed.repo, "Vapor-Deployer")
        XCTAssertNil(SetupValidator.parseGitHubSSHURL("https://github.com/mottzi/Vapor-Deployer.git"))
    }

    func testPanelRouteNormalization() {
        XCTAssertEqual(SetupValidator.normalizePanelRoute("deployer"), "/deployer")
        XCTAssertEqual(SetupValidator.normalizePanelRoute("/deployer/"), "/deployer")
        XCTAssertEqual(SetupValidator.normalizePanelRoute("/"), "/")
    }

    func testAliasDomainDerivationTogglesWWW() {
        XCTAssertEqual(SetupValidator.deriveAliasDomain(from: "example.com"), "www.example.com")
        XCTAssertEqual(SetupValidator.deriveAliasDomain(from: "www.example.com"), "example.com")
    }

}
