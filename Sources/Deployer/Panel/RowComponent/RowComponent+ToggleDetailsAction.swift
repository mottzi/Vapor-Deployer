import Vapor
import Mist

extension RowComponent {

    struct ToggleDetailsAction: Action {

        let name: String = "toggleDetails"
        let productName: String

        func perform(targetID: UUID?, state: inout ComponentState, app: Application) async -> ActionResult {
            
            guard let targetID,
                  let deployment = await loadDeployment(id: targetID, product: productName, app: app),
                  deployment.hasDetails
            else { return .failure("Deployment not found or no details to display.") }
            
            let current = state["detailsExpanded"]?.bool ?? false
            state["detailsExpanded"] = .bool(!current)
            
            return .success()
        }

    }

}
