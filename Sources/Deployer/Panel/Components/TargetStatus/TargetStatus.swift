import Vapor
import Mist
import Elementary

struct TargetStatus: LiveComponent {

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

    init(product: String, state: LiveState<StatusState>) {
        self.product = product
        self.name = "TargetStatus"
        self.state = state
        self.actions = []
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
