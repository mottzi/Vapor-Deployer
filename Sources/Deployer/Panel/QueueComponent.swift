import Vapor
import Mist
import Elementary

struct QueueComponent: LiveComponent {
    
    let state = LiveState(of: QueueState(isDeploying: false))

    func refresh(app: Application) async {
        let isDeploying = await app.deployer.queue.isDeploying
        await state.set(QueueState(isDeploying: isDeploying))
    }
    
    func body(state: QueueState) -> some HTML {
        span(
            .class("dp-supervisor-badge \(state.badgeClass)"),
            .mistComponent(value: self.name),
            .title(state.tooltip),
            .custom(name: "aria-label", value: state.tooltip)
        ) {
            switch state.isDeploying {
                case true: "Locked"
                case false: "Unlocked"
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
