import XCTest
@testable import deployer

final class ShellStreamingTests: XCTestCase {

    func testStreamingTailDrainsLargeOutputWithoutDeadlock() async {
        let result = await Shell.runStreamingTail([
            "bash",
            "-c",
            "for i in $(seq 1 20000); do echo line$i; done"
        ], forceTTY: false)

        XCTAssertEqual(result.exitCode, 0)
        let lines = result.output.split(separator: "\n")
        XCTAssertEqual(lines.count, 20_000)
        XCTAssertEqual(lines.first, "line1")
        XCTAssertEqual(lines.last, "line20000")
    }

}
