import Vapor
import Mist

extension RowComponent {
    
    struct RemoveBinaryAction: Action {
        
        let name: String = "removeBinary"
        let productName: String
        
        func perform(targetID: UUID?, state: inout ComponentState, app: Application) async -> ActionResult {
            
            guard let targetID,
                  let deployment = await loadDeployment(id: targetID, product: productName, app: app),
                  deployment.hasSavedBinary
            else { return .failure("Deployment not found or doesn't have a saved binary.") }
            
            let target = app.deployer.queue.config.target
            let store = BinaryStore(target: target)
            guard store.hasBinary(for: deployment)
            else { return .failure("Saved binary not found on disk") }
            
            do {
                try store.deleteBinary(for: deployment)
                deployment.binarySizeMB = nil
                deployment.isManuallySaved = false
                deployment.output = nil
                deployment.status = .pushed
                try await deployment.save(on: app.db)
            }
            catch {
                let mistError = MistError.databaseFetchFailed(
                    "Binary delete id=\(deployment.id?.uuidString ?? "nil")",
                    error
                )
                app.logger.error("\(mistError)")
                return .failure("Failed to remove binary")
            }
            
            return .success()
        }
        
    }
    
}
