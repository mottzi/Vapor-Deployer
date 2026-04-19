import XCTest
@testable import deployer

final class SetupValidatorsTests: XCTestCase {

    func testSafeNameMatchesInstallerConstraints() {
        XCTAssertTrue(SetupValidators.isSafeName("mottzi"))
        XCTAssertTrue(SetupValidators.isSafeName("my-app_1.2"))
        XCTAssertFalse(SetupValidators.isSafeName(""))
        XCTAssertFalse(SetupValidators.isSafeName("my app"))
        XCTAssertFalse(SetupValidators.isSafeName("my/app"))
    }

    func testPortValidationRejectsOutOfRangeValues() {
        XCTAssertTrue(SetupValidators.isValidPort("1"))
        XCTAssertTrue(SetupValidators.isValidPort("8080"))
        XCTAssertTrue(SetupValidators.isValidPort("65535"))
        XCTAssertFalse(SetupValidators.isValidPort("0"))
        XCTAssertFalse(SetupValidators.isValidPort("65536"))
        XCTAssertFalse(SetupValidators.isValidPort("abc"))
    }

    func testEmailValidationCoversInstallerShape() {
        XCTAssertTrue(SetupValidators.isValidEmail("admin@example.com"))
        XCTAssertTrue(SetupValidators.isValidEmail("first.last+deploy@example.co.uk"))
        XCTAssertFalse(SetupValidators.isValidEmail("admin"))
        XCTAssertFalse(SetupValidators.isValidEmail("admin@example"))
        XCTAssertFalse(SetupValidators.isValidEmail("@example.com"))
    }

    func testPublicBaseURLRequiresHTTPSDomainWithoutPathOrPort() {
        XCTAssertTrue(SetupValidators.isValidPublicBaseURL("https://example.com"))
        XCTAssertTrue(SetupValidators.isValidPublicBaseURL("https://www.example.com/"))
        XCTAssertFalse(SetupValidators.isValidPublicBaseURL("http://example.com"))
        XCTAssertFalse(SetupValidators.isValidPublicBaseURL("https://example.com:8443"))
        XCTAssertFalse(SetupValidators.isValidPublicBaseURL("https://example.com/path"))
        XCTAssertFalse(SetupValidators.isValidPublicBaseURL("https://localhost"))
    }

    func testGitHubSSHURLParsingNormalizesRepositorySuffix() throws {
        let parsed = try XCTUnwrap(SetupValidators.parseGitHubSSHURL("git@github.com:mottzi/Vapor-Deployer.git"))
        XCTAssertEqual(parsed.owner, "mottzi")
        XCTAssertEqual(parsed.repo, "Vapor-Deployer")
        XCTAssertNil(SetupValidators.parseGitHubSSHURL("https://github.com/mottzi/Vapor-Deployer.git"))
    }

    func testPanelRouteNormalization() {
        XCTAssertEqual(SetupValidators.normalizePanelRoute("deployer"), "/deployer")
        XCTAssertEqual(SetupValidators.normalizePanelRoute("/deployer/"), "/deployer")
        XCTAssertEqual(SetupValidators.normalizePanelRoute("/"), "/")
    }

    func testAliasDomainDerivationTogglesWWW() {
        XCTAssertEqual(SetupValidators.deriveAliasDomain(from: "example.com"), "www.example.com")
        XCTAssertEqual(SetupValidators.deriveAliasDomain(from: "www.example.com"), "example.com")
    }

}
