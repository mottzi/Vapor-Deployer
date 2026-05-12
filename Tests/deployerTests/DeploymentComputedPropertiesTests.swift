import XCTest
import Mist
@testable import deployer

final class DeploymentComputedPropertiesTests: XCTestCase {

    func testComputedPropertiesAreVisibleThroughMistModelExistential() {
        let id = UUID(uuidString: "A1B2C3D4-E5F6-7890-ABCD-EF1234567890")!
        let startedAt = Date(timeIntervalSince1970: 1_000)
        let finishedAt = Date(timeIntervalSince1970: 1_002.5)

        let deployment = Deployment(
            product: "mottzi",
            status: .success,
            commitMessage: "template fix",
            commitID: "abcdef123456",
            branch: "dev"
        )
        deployment.id = id
        deployment.startedAt = startedAt
        deployment.finishedAt = finishedAt

        let model: any Mist.Model = deployment
        let properties = model.computedProperties

        XCTAssertEqual(properties["displayStatus"] as? String, "success")
        XCTAssertEqual(properties["shortID"] as? String, "A1B2C3D4")
        XCTAssertEqual(properties["startedAtUnixMs"] as? Int, 1_000_000)
        XCTAssertEqual(properties["durationString"] as? String, "2.5s")
        XCTAssertEqual(properties["canBeDeployed"] as? Bool, true)
        XCTAssertEqual(properties["canBuild"] as? Bool, true)
        XCTAssertEqual(properties["canRestoreBinary"] as? Bool, false)
        XCTAssertEqual(properties["hasSavedBinary"] as? Bool, false)
        XCTAssertEqual(properties["hasDetails"] as? Bool, false)
        XCTAssertEqual(properties["hasLiveOutputStream"] as? Bool, false)
    }

    func testSavedBinaryComputedProperties() {
        let deployment = Deployment(
            product: "mottzi",
            status: .success,
            commitMessage: "template fix",
            commitID: "abcdef123456",
            branch: "dev"
        )
        deployment.binarySizeMB = 18

        XCTAssertEqual(deployment.hasSavedBinary, true)
        XCTAssertEqual(deployment.canBuild, false)
        XCTAssertEqual(deployment.canRestoreBinary, true)
    }

}
