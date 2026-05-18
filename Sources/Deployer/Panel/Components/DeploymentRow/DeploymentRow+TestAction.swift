import Vapor
import Mist

extension DeploymentRow {

    struct TestAction: Action {

        let name: String = "test"
        let productName: String

        func perform(targetID: UUID?, state: inout ComponentState, app: Application) async -> ActionResult {

            // Shares `canBuild` with Save-binary/Deploy: a test run only makes sense on a snapshot
            // that has not yet been promoted to a binary (i.e. still in the pre-build realm).
            guard let targetID,
                  let deployment = await loadDeployment(id: targetID, product: productName, app: app),
                  deployment.canBuild
            else { return .failure("Deployment not found or can't be tested.") }

            let result = await app.deployer.queue.test(
                deployment: deployment,
                target: app.deployer.queue.config.target
            )

            return switch result {
                case .started: .success("Test run started")
                case .queueBusy: .failure("A deployment is already running")
                case .failure(let message): .failure(message)
            }
        }

    }

}
