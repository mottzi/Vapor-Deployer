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
            .class("dp-state-badge \(state.badgeClass)"),
            .mistComponent(self.name),
            .mistMinDuration(ms: 1000),
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

    static func resolve(
        updaterIsUpdating: Bool = false,
        operationIsDeploying: Bool = false
    ) -> DeployerPhase {

        if updaterIsUpdating { return .updating }

        if UpdateLock.isHeld() { return .updating }
        if OperationLock.isHeld() || operationIsDeploying { return .deploying }

        return .ready
    }

    var label: String {
        switch self {
            case .ready: "Ready"
            case .deploying: "Busy"
            case .updating: "Updating"
        }
    }

    var badgeClass: String {
        switch self {
            case .ready: "dp-state-badge--operation-unlocked"
            case .deploying: "dp-state-badge--operation-locked"
            case .updating: "dp-state-badge--operation-updating"
        }
    }

    var tooltip: String {
        switch self {
            case .ready: "Operations ready"
            case .deploying: "Operation in progress"
            case .updating: "Deployer is self-updating"
        }
    }

}
