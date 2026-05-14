import Vapor
import Mist

extension StatusComponent {

    struct RestartAction: Action {

        let name = "restart"
        let productName: String
        let badgeState: LiveState<StatusState>
        let actionsState: LiveState<StatusState>

        func perform(targetID: UUID?, state: inout ComponentState, app: Application) async -> ActionResult {

            do {
                let manager = app.deployer.serviceManager
                let status = await manager.status(product: productName)
                switch status.isRunning {
                    case true:
                        await badgeState.set(StatusState(.stopping))
                        await actionsState.set(StatusState(.stopping))
                    case false:
                        await badgeState.set(StatusState(.starting))
                        await actionsState.set(StatusState(.starting))
                }

                try await manager.restart(product: productName)
                await badgeState.set(StatusState(.starting))
                await actionsState.set(StatusState(.starting))

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
