import Vapor
import Mist
import Elementary

struct TargetStatusActions: LiveComponent {

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
            .mistMinDuration(ms: 1000),
            .mistSSR(true)
        ) {
            if state.isRunning {
                stopButton
            }
            startButton
        }
    }

    init(product: String, state: LiveState<StatusState>, broadcaster: TargetStatusBroadcaster) {
        self.product = product
        self.name = "TargetStatusActions"
        self.state = state
        self.actions = [
            TargetStatus.RestartAction(productName: product, broadcaster: broadcaster),
            TargetStatus.StopAction(productName: product, broadcaster: broadcaster)
        ]
    }

}
