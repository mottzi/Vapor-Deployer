import Vapor
import Mist

extension StatusComponent {

    struct RestartAction: Action {

        let name = "restart"
        let productName: String
        let broadcaster: StatusBroadcaster

        func perform(targetID: UUID?, state: inout ComponentState, app: Application) async -> ActionResult {

            do {
                let manager = app.deployer.serviceManager
                let status = await manager.status(product: productName)
                await broadcaster.set(StatusState(status.isRunning ? .stopping : .starting))

                try await manager.restart(product: productName)
                await broadcaster.set(StatusState(.starting))

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
