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
    
    func body(state: StatusState) -> some HTML {
        div(
            .class("dp-product-status"),
            .mistComponent(value: "StatusComponent-\(product)")
        ) {
            if state.isRunning { stopButton }
            if !state.isTransitioning { startButton }
            statusBadge(of: state)
        }
    }
    
    init(
        product: String,
        status: DeployerServiceStatus
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

    init(_ status: DeployerServiceStatus) {
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
            .title("Stop")
        ) {
            HTMLRaw(
                """
                <svg width="11" height="11" viewBox="0 0 24 24" fill="currentColor" xmlns="http://www.w3.org/2000/svg">
                  <rect x="4" y="4" width="16" height="16" rx="2"/>
                </svg>
                """
            )
        }
    }
    
    var startButton: some HTML {
        button(
            .class("dp-supervisor-btn dp-supervisor-btn--restart"),
            .custom(name: "mist-action", value: "restart"),
            .title("Restart")
        ) {
            HTMLRaw(
                """
                <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" xmlns="http://www.w3.org/2000/svg">
                  <polyline points="23 4 23 10 17 10"/>
                  <path d="M20.49 15a9 9 0 1 1-2.12-9.36L23 10"/>
                </svg>
                """
            )
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
            statusDot
            "running"
        }
    }

    var fatalBadge: some HTML {
        span(.class("dp-supervisor-badge dp-supervisor-badge--fatal")) {
            statusDot
            "fatal"
        }
    }

    var statusDot: some HTML {
        span(.class("dp-supervisor-dot")) {}
    }

    var pulsingStatusDot: some HTML {
        span(.class("dp-supervisor-dot dp-supervisor-dot--pulse")) {}
    }

    func transitioningBadge(_ status: String) -> some HTML {
        span(.class("dp-supervisor-badge dp-supervisor-badge--transitioning")) {
            pulsingStatusDot
            status
        }
    }

    func stoppedBadge(_ status: String) -> some HTML {
        span(.class("dp-supervisor-badge dp-supervisor-badge--stopped")) {
            statusDot
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
