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

    func testShellCommandKeepsSimpleCommandsCopyPasteable() {
        XCTAssertEqual(
            TemplateEscaping.shellCommand([
                "sudo", "certbot", "certonly",
                "--webroot",
                "--email", "sayilir.berken@gmail.com",
                "--cert-name", "mottzi.codes",
                "-w", "/var/www/certbot/mottzi",
                "-d", "www.mottzi.codes"
            ]),
            "sudo certbot certonly --webroot --email sayilir.berken@gmail.com --cert-name mottzi.codes -w /var/www/certbot/mottzi -d www.mottzi.codes"
        )
    }

    func testShellCommandQuotesArgumentsOnlyWhenNeeded() {
        XCTAssertEqual(
            TemplateEscaping.shellCommand(["printf", "hello world", "it's"]),
            #"printf 'hello world' 'it'"'"'s'"#
        )
    }

}
