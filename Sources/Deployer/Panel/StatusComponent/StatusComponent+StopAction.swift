import Vapor
import Mist

extension StatusComponent {

    struct StopAction: Action {

        let name = "stop"
        let productName: String
        let broadcaster: StatusBroadcaster

        func perform(targetID: UUID?, state: inout ComponentState, app: Application) async -> ActionResult {

            do {
                let manager = app.deployer.serviceManager
                await broadcaster.set(StatusState(.stopping))
                try await manager.stop(product: productName)

                let finalStatus = await manager.status(product: productName)
                await broadcaster.set(StatusState(finalStatus))

                return .success()
            } catch {
                let manager = app.deployer.serviceManager
                let recoveryStatus = await manager.status(product: productName)
                await broadcaster.set(StatusState(recoveryStatus))
                return .failure(error.localizedDescription)
            }
        }

    }

}
