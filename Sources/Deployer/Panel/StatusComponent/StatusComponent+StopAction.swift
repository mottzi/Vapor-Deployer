import Vapor
import Mist

extension StatusComponent {

    struct StopAction: Action {

        let name = "stop"
        let productName: String
        let badgeState: LiveState<StatusState>
        let actionsState: LiveState<StatusState>

        func perform(targetID: UUID?, state: inout ComponentState, app: Application) async -> ActionResult {

            do {
                let manager = app.deployer.serviceManager
                await badgeState.set(StatusState(.stopping))
                await actionsState.set(StatusState(.stopping))
                try await manager.stop(product: productName)

                let finalStatus = await manager.status(product: productName)
                await badgeState.set(StatusState(finalStatus))
                await actionsState.set(StatusState(finalStatus))

                return .success()
            } catch {
                let manager = app.deployer.serviceManager
                let recoveryStatus = await manager.status(product: productName)
                await badgeState.set(StatusState(recoveryStatus))
                await actionsState.set(StatusState(recoveryStatus))
                return .failure(error.localizedDescription)
            }
        }

    }

}
