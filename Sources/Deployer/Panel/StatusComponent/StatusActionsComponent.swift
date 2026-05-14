import Vapor
import Mist
import Elementary

struct StatusActionsComponent: LiveComponent {

    var name: String
    let product: String
    var actions: [Action]
    let state: LiveState<StatusState>

    // Shared state is updated via StatusComponent or external events
    func refresh(app: Application) async { }

    func body(state: StatusState) -> some HTML {
        div(
            .class("dp-target-actions"),
            .mistComponent(name),
            .mistDelay(ms: 1000),
            .mistSSR(true)
        ) {
            if state.isRunning {
                stopButton
            }
            startButton
        }
    }

    init(product: String, state: LiveState<StatusState>, broadcaster: StatusBroadcaster) {
        self.product = product
        self.name = "StatusActionsComponent"
        self.state = state
        self.actions = [
            StatusComponent.RestartAction(productName: product, broadcaster: broadcaster),
            StatusComponent.StopAction(productName: product, broadcaster: broadcaster)
        ]
    }

}
