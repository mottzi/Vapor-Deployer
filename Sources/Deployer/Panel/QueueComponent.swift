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
            .class("dp-queue-lock \(state.lockedClass)"),
            .mistComponent(value: self.name)
        ) {
            switch state.isDeploying {
                case true: lockedIcon
                case false: unlockedIcon
            }
        }
    }
    
    let lockedIcon = HTMLRaw(
        """
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
          <rect x="5" y="11" width="14" height="10" rx="2"></rect>
          <path d="M8 11V8a4 4 0 0 1 8 0v3"></path>
        </svg>
        """
    )

    let unlockedIcon = HTMLRaw(
        """
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
          <rect x="5" y="11" width="14" height="10" rx="2"></rect>
          <path d="M8 11V8a4 4 0 0 1 7-2.8"></path>
          <path d="M15 8l2.5-2.5"></path>
        </svg>
        """
    )

}

struct QueueState: ComponentData {

    let isDeploying: Bool
    
    var lockedClass: String {
        isDeploying
            ? "dp-queue-lock--locked"
            : "dp-queue-lock--unlocked"
    }

}
