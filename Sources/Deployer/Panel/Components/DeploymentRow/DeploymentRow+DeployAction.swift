import Vapor
import Mist

extension DeploymentRow {
    
    struct DeployAction: Action {
        
        let name: String = "deploy"
        let productName: String
        
        func perform(targetID: UUID?, state: inout ComponentState, app: Application) async -> ActionResult {
            
            guard let targetID,
                  let deployment = await loadDeployment(id: targetID, product: productName, app: app),
                  deployment.canBuild
            else { return .failure("Deployment not found or can't be built.") }
            
            let result = await app.deployer.operations.deploy(
                deployment: deployment,
                target: app.deployer.operations.config.target
            )
            
            return switch result {
            case .started: .success("Deployment started")
            case .operationBusy: .failure("A deployment is already running")
            case .failure(let message): .failure(message)
            }
        }
        
    }
    
}
