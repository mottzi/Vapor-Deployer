import Vapor
import Mist

extension DeploymentRow {
    
    struct DeleteAction: Action {
        
        let name: String = "delete"
        let productName: String
        
        func perform(targetID: UUID?, state: inout ComponentState, app: Application) async -> ActionResult {
            
            guard let targetID,
                  let deployment = await loadDeployment(id: targetID, product: productName, app: app)
            else { return .failure("Deployment not found") }
            
            guard !deployment.isLive else {
                return .failure("Cannot delete the active live deployment")
            }
            
            do {
                try await deployment.delete(on: app.db)
            }
            catch {
                let error = MistError.databaseFetchFailed(
                    "Deployment delete id=\(deployment.id?.uuidString ?? "nil")",
                    error
                )
                app.logger.error("\(error)")
                return .failure("Failed to delete deployment")
            }
            
            return .success()
        }
        
    }
    
}
