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
    
    /// Badge only — Stop/Restart live in `DeployerPanel.leaf` and route actions via `mist-actions-for`.
    func body(state: StatusState) -> some HTML {
        div(
            .class("dp-product-status"),
            .mistComponent(value: "StatusComponent-\(product)")
        ) {
            statusBadge(of: state)
        }
    }
    
    init(
        product: String,
        status: ServiceStatus
    ) {
        self.product = product
        self.name = "StatusComponent-\(product)"
        self.state = LiveState(of: StatusState(status))
        self.actions = [
            RestartAction(productName: product, reactiveState: state),
            StopAction(productName: product, reactiveState: state)
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

extension StatusComponent {
    
    var stopButton: some HTML {
        button(
            .class("dp-supervisor-btn dp-supervisor-btn--stop"),
            .custom(name: "mist-action", value: "stop"),
            .title("Stop service")
        ) {
            HTMLRaw(
                """
                <svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
                  <rect x="4" y="4" width="16" height="16" rx="2"/>
                </svg>
                """
            )
            "Stop"
        }
    }
    
    var startButton: some HTML {
        button(
            .class("dp-supervisor-btn dp-supervisor-btn--restart"),
            .custom(name: "mist-action", value: "restart"),
            .title("Restart service")
        ) {
            HTMLRaw(
                """
                <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
                  <path d="M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8"/>
                  <path d="M3 3v5h5"/>
                </svg>
                """
            )
            "Restart"
        }
    }
    
}

extension StatusComponent {
    
    @HTMLBuilder
    func statusBadge(of state: StatusState) -> some HTML {
        
        switch (state.isTransitioning, state.isRunning, state.status) {
            case (true, _, let status): transitioningBadge(status)
            case (false, true, _): runningBadge
            case (false, false, "fatal"): fatalBadge
            case (false, false, let status): stoppedBadge(status)
        }
    }

    var runningBadge: some HTML {
        span(.class("dp-supervisor-badge dp-supervisor-badge--running")) {
            "running"
        }
    }

    var fatalBadge: some HTML {
        span(.class("dp-supervisor-badge dp-supervisor-badge--fatal")) {
            "fatal"
        }
    }

    func transitioningBadge(_ status: String) -> some HTML {
        span(.class("dp-supervisor-badge dp-supervisor-badge--transitioning")) {
            status
        }
    }

    func stoppedBadge(_ status: String) -> some HTML {
        span(.class("dp-supervisor-badge dp-supervisor-badge--stopped")) {
            status
        }
    }
    
}

extension StatusComponent {

    struct RestartAction: Action {

        let name = "restart"
        let productName: String
        let reactiveState: LiveState<StatusState>

        func perform(targetID: UUID?, state: inout ComponentState, app: Application) async -> ActionResult {

            do {
                let manager = app.deployer.serviceManager
                let status = await manager.status(product: productName)
                switch status.isRunning {
                    case true: await reactiveState.set(StatusState(.stopping))
                    case false: await reactiveState.set(StatusState(.starting))
                }

                try await manager.restart(product: productName)
                await reactiveState.set(StatusState(.starting))

                let finalStatus = await manager.status(product: productName)
                await reactiveState.set(StatusState(finalStatus))

                return .success()
            } catch {
                let manager = app.deployer.serviceManager
                let recoveryStatus = await manager.status(product: productName)
                await reactiveState.set(StatusState(recoveryStatus))
                return .failure(error.localizedDescription)
            }
        }

    }

    struct StopAction: Action {

        let name = "stop"
        let productName: String
        let reactiveState: LiveState<StatusState>

        func perform(targetID: UUID?, state: inout ComponentState, app: Application) async -> ActionResult {

            do {
                let manager = app.deployer.serviceManager
                await reactiveState.set(StatusState(.stopping))
                try await manager.stop(product: productName)

                let finalStatus = await manager.status(product: productName)
                await reactiveState.set(StatusState(finalStatus))

                return .success()
            } catch {
                let manager = app.deployer.serviceManager
                let recoveryStatus = await manager.status(product: productName)
                await reactiveState.set(StatusState(recoveryStatus))
                return .failure(error.localizedDescription)
            }
        }

    }

}
