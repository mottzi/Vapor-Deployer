import Vapor
import Mist

extension DeploymentRow {
    
    struct SaveBinaryAction: Action {
        
        let name: String = "saveBinary"
        let productName: String
        
        func perform(targetID: UUID?, state: inout ComponentState, app: Application) async -> ActionResult {
            
            guard let targetID,
                  let deployment = await loadDeployment(id: targetID, product: productName, app: app),
                  deployment.canBuild
            else { return .failure("Deployment not found or can't be built.") }
            
            let target = app.deployer.operations.config.target
            let store = BinaryStore(target: target)
            guard !store.hasBinary(for: deployment)
            else { return .failure("This deployment already has a saved binary") }
            
            let result = await app.deployer.operations.saveBinary(
                deployment: deployment,
                target: target
            )
            
            return switch result {
            case .started: .success("Binary save started")
            case .operationBusy: .failure("A deployment is already running")
            case .failure(let message): .failure(message)
            }
        }
        
    }
    
}
