import XCTest
@testable import deployer

final class BinaryBehaviourTests: XCTestCase {

    func testSetupInputParserAcceptsSupportedPolicies() {
        XCTAssertEqual(BinaryBehaviour.parse("newest:5"), .newest(count: 5))
        XCTAssertEqual(BinaryBehaviour.parse("automatic:500"), .automatic(mb: 500))
        XCTAssertEqual(BinaryBehaviour.parse("auto 250"), .automatic(mb: 250))
        XCTAssertEqual(BinaryBehaviour.parse("all"), .all)
        XCTAssertEqual(BinaryBehaviour.parse("off"), .off)
    }

    func testSetupInputParserRejectsInvalidPolicies() {
        XCTAssertNil(BinaryBehaviour.parse(""))
        XCTAssertNil(BinaryBehaviour.parse("newest:0"))
        XCTAssertNil(BinaryBehaviour.parse("automatic:-1"))
        XCTAssertNil(BinaryBehaviour.parse("oldest:5"))
    }

    func testTargetConfigurationRequiresBinaryBehaviour() throws {
        let json = """
        {
          "name": "mottzi",
          "repositoryURL": null,
          "directory": "../apps/mottzi",
          "buildMode": "release",
          "pusheventPath": "/pushevent/mottzi",
          "deploymentMode": "manual",
          "appPort": 8080,
          "branch": "main"
        }
        """

        XCTAssertThrowsError(try JSONDecoder().decode(TargetConfiguration.self, from: Data(json.utf8)))
    }

}
