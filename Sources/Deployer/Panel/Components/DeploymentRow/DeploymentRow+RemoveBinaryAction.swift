import Vapor
import Mist

extension DeploymentRow {
    
    struct RemoveBinaryAction: Action {
        
        let name: String = "removeBinary"
        let productName: String
        
        func perform(targetID: UUID?, state: inout ComponentState, app: Application) async -> ActionResult {
            
            guard let targetID,
                  let deployment = await loadDeployment(id: targetID, product: productName, app: app),
                  deployment.hasSavedBinary
            else { return .failure("Deployment not found or doesn't have a saved binary.") }

            guard !deployment.isLive else {
                return .failure("Cannot remove the saved binary for the active live deployment")
            }
            
            let target = app.deployer.queue.config.target
            let store = BinaryStore(target: target)
            guard store.hasBinary(for: deployment)
            else { return .failure("Saved binary not found on disk") }

            let lock: OperationLock
            do {
                let installDirectory = try Configuration.getExecutableURL().deletingLastPathComponent()
                lock = try OperationLock.acquire(installDirectory: installDirectory)
            } catch OperationError.anotherOperationInProgress {
                return .failure("A deployment is already running")
            } catch {
                return .failure(error.localizedDescription)
            }

            do {
                defer { _ = lock }
                let engine = OperationEngine(app: app, config: app.deployer.queue.config)
                try await engine.run(action: .removeBinary, deployment: deployment)
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
