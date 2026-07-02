import Vapor
import Mist

extension DeploymentRow {
    
    struct RestoreBinaryAction: Action {
        
        let name: String = "restoreBinary"
        let productName: String
        
        func perform(targetID: UUID?, state: inout ComponentState, app: Application) async -> ActionResult {
            
            guard let targetID,
                  let deployment = await loadDeployment(id: targetID, product: productName, app: app),
                  deployment.canRestoreBinary
            else { return .failure("Deployment not found or can't restore its binary.") }
            
            let target = app.deployer.operations.config.target
            let store = DeploymentBinaryStore(target: target)
            guard store.hasBinary(for: deployment)
            else { return .failure("Saved binary not found on disk") }
            
            let result = await app.deployer.operations.restoreBinary(
                deployment: deployment,
                target: target
            )
            
            return switch result {
            case .started: .success("Binary restore started")
            case .operationBusy: .failure("A deployment is already running")
            case .failure(let message): .failure(message)
            }
        }
        
    }
    
}
