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

            let lock: OperationLock
            do {
                lock = try OperationLock.acquire()
            } catch Operation.Error.anotherOperationInProgress {
                return .failure("A deployment is already running")
            } catch {
                return .failure(error.localizedDescription)
            }

            do {
                defer { lock.release() }
                let engine = OperationEngine(app: app, config: app.deployer.operations.config)
                try await engine.run(action: .delete, deployment: deployment)
                app.logger.info("Deleted deployment for commit \(deployment.commitID.prefix(7))")
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
