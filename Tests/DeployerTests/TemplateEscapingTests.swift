import XCTest
@testable import deployer

final class TemplateEscapingTests: XCTestCase {

    func testEnvironmentValueEscapesSystemdAndSupervisorSpecialCharacters() {
        let raw = "quote\" slash\\ newline\ntab\tcarriage\rdone"

        XCTAssertEqual(
            TemplateEscaping.environmentValue(raw),
            #"quote\" slash\\ newline\ntab\tcarriage\rdone"#
        )
    }

}
