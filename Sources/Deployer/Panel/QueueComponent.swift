import Vapor
import Mist
import Elementary

struct QueueComponent: ManualComponent {

    let state = LiveState(of: QueueState(isDeploying: false))

    func body(state: QueueState) -> some HTML {
        span(
            .class("dp-supervisor-badge \(state.badgeClass)"),
            .mistComponent(self.name),
            .title(state.tooltip),
            .custom(name: "aria-label", value: state.tooltip)
        ) {
            switch state.isDeploying {
                case true: "Busy"
                case false: "Ready"
            }
        }
    }

}

struct QueueState: ComponentData {

    let isDeploying: Bool
    
    var badgeClass: String {
        isDeploying
            ? "dp-supervisor-badge--queue-locked"
            : "dp-supervisor-badge--queue-unlocked"
    }

    var tooltip: String {
        isDeploying
            ? "Queue locked — deployment in progress"
            : "Queue unlocked — ready"
    }

}
