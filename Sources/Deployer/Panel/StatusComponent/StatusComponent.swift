import Vapor
import Mist
import Elementary

struct StatusComponent: LiveComponent {

    var name: String
    let product: String
    var actions: [Action]
    let state: LiveState<StatusState>

    func refresh(app: Application) async {
        let currentStatus = await app.deployer.serviceManager.status(product: product)
        await state.set(StatusState(currentStatus))
    }

    func body(state: StatusState) -> some HTML {
        div(
            .class("dp-product-status"),
            .mistComponent(name),
            .mistDelay(ms: 1000),
            .mistSSR(true)
        ) {
            statusBadge(of: state)
        }
    }

    init(
        product: String,
        badgeState: LiveState<StatusState>,
        actionsState: LiveState<StatusState>
    ) {
        self.product = product
        self.name = "StatusComponent"
        self.state = badgeState
        self.actions = [
            RestartAction(productName: product, badgeState: badgeState, actionsState: actionsState),
            StopAction(productName: product, badgeState: badgeState, actionsState: actionsState)
        ]
    }

}

struct StatusState: ComponentData {

    let status: String
    let isRunning: Bool
    let isTransitioning: Bool

    init(_ status: ServiceStatus) {
        self.status = status.label
        self.isRunning = status.isRunning
        self.isTransitioning = status.isTransitioning
    }

}
