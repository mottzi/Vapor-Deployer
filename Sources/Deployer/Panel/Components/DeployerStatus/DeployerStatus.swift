import Vapor
import Mist
import Elementary

struct DeployerStatus: ManualComponent {

    let state: LiveState<DeployerPhase>
    let actions: [any Action]

    init(state: LiveState<DeployerPhase>, updater: Updater) {
        self.state = state
        self.actions = [UpdateAction(updater: updater)]
    }

    func body(state: DeployerPhase) -> some HTML {
        span(
            .class("dp-supervisor-badge \(state.badgeClass)"),
            .mistComponent(self.name),
            .mistDebounce(ms: 500),
            .title(state.tooltip),
            .custom(name: "aria-label", value: state.tooltip)
        ) {
            state.label
        }
    }

}

enum DeployerPhase: String, ComponentData {

    case ready
    case deploying
    case updating

    var label: String {
        switch self {
            case .ready: "Ready"
            case .deploying: "Busy"
            case .updating: "Updating"
        }
    }

    var badgeClass: String {
        switch self {
            case .ready: "dp-supervisor-badge--queue-unlocked"
            case .deploying: "dp-supervisor-badge--queue-locked"
            case .updating: "dp-supervisor-badge--queue-updating"
        }
    }

    var tooltip: String {
        switch self {
            case .ready: "Queue unlocked — ready"
            case .deploying: "Queue locked — deployment in progress"
            case .updating: "Deployer is self-updating"
        }
    }

}
