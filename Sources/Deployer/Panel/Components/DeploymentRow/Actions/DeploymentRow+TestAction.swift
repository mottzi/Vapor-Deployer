import Vapor
import Mist

extension DeploymentRow {

    struct TestAction: Action {

        let name: String = "test"
        let productName: String

        func perform(targetID: UUID?, state: inout ComponentState, app: Application) async -> ActionResult {

            // Permissive: allowed on every non-actively-transient row including `.running`. Tests are
            // pure audits — they never alter status. Env can drift; the user owns re-verification.
            guard let targetID,
                  let deployment = await loadDeployment(id: targetID, product: productName, app: app),
                  deployment.canTest
            else { return .failure("Deployment not found or can't be tested.") }

            let result = await app.deployer.operations.test(
                deployment: deployment,
                target: app.deployer.operations.config.target
            )

            return result.actionResult(success: "Test run started")
        }

    }

}
