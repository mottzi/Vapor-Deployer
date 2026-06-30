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
        installDirectory: URL?,
        updaterIsUpdating: Bool = false,
        queueIsDeploying: Bool = false
    ) -> DeployerPhase {

        if updaterIsUpdating { return .updating }

        guard let installDirectory else {
            return queueIsDeploying ? .deploying : .ready
        }

        if UpdateLock.isHeld(installDirectory: installDirectory) { return .updating }
        if OperationLock.isHeld(installDirectory: installDirectory) || queueIsDeploying { return .deploying }

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
            case .ready: "dp-state-badge--queue-unlocked"
            case .deploying: "dp-state-badge--queue-locked"
            case .updating: "dp-state-badge--queue-updating"
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
