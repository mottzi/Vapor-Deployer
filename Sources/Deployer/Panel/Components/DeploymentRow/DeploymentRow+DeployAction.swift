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
            
            switch result {
                case .started:
                    app.logger.info("Started deployment (Branch: \(deployment.branch), Commit: \(deployment.commitID.prefix(7)))")
                    
                    return .success("Deployment started")
                case .operationBusy:
                    return .failure("A deployment is already running")
                case .failure(let message):
                    return .failure(message)
            }
        }
        
    }
    
}
