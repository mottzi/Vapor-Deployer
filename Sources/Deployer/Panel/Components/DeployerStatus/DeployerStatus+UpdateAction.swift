import Vapor
import Mist

extension DeployerStatus {
    
    /// Mist action exposed by `DeployerStatus` to trigger a self-update from the panel.
    struct UpdateAction: Action {

        let name = "update"
        let updater: Updater

        func perform(targetID: UUID?, state: inout ComponentState, app: Application) async -> ActionResult {

            switch await updater.startUpdate() {
                case .started: return .success()
                case .busy: return .failure("Deployer is busy")
                case .failure(let message): return .failure(message)
            }
        }

    }
    
}
