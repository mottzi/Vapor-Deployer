import Vapor
import Fluent
import Mist

public struct StatusComponent: Mist.StateComponent {

    public let productName: String

    public var name: String { "StatusComponent-\(productName)" }
    public let interval: Duration = .seconds(3)
    public let template: Template = .file(path: "Deployer/StatusComponent")
    public let actions: [any Mist.Action]
    public let reactiveState: ReactiveState<State>

    public init(productName: String) {
        self.productName = productName

        let state = ReactiveState<State>(
            initialState: State(productName: productName, status: .unknown)
        )

        self.reactiveState = state

        self.actions = [
            RestartAction(productName: productName, reactiveState: state),
            StopAction(productName: productName, reactiveState: state)
        ]
    }

    // MARK: - State Definition

    /// The component's reactive state: the product name (for template rendering)
    /// and the current Supervisor status.
    public struct State: Encodable, Equatable, Sendable {
        public let productName: String
        public let status: String
        public let isRunning: Bool
        public let isTransitioning: Bool

        public init(productName: String, status: DeployerShell.Supervisor.Status) {
            self.productName = productName
            self.status = status.label
            self.isRunning = status.isRunning
            self.isTransitioning = status.isTransitioning
        }
    }

    // MARK: - Background Observation

    /// Continuous background loop that observes the real Supervisor process state
    /// and pushes updates to the reactive state actor. Yields whenever a user action
    /// is actively manipulating the state (via `shouldPause`).
    public func observe(app: Application) async {

        // Immediately query and push the ground truth on startup
        let initialStatus = await DeployerShell.Supervisor.status(product: productName)
        await reactiveState.set(State(productName: productName, status: initialStatus))

        // Continuous observation loop
        while !app.didShutdown && !Task.isCancelled {

            try? await Task.sleep(for: interval)
            guard !app.didShutdown && !Task.isCancelled else { break }

            // Yield to active user actions — skip this tick
            guard !await shouldPause(on: app) else { continue }

            let currentStatus = await DeployerShell.Supervisor.status(product: productName)
            await reactiveState.set(State(productName: productName, status: currentStatus))
        }
    }

}

// MARK: - Actions

extension StatusComponent {

    /// Restart action: orchestrates a stop → start sequence with intermediate
    /// visual state transitions pushed to the reactive state actor.
    struct RestartAction: Mist.Action {

        let name = "restart"
        let productName: String
        let reactiveState: ReactiveState<State>

        func perform(id: UUID?, state: inout MistState, on db: Database) async -> ActionResult {
            do {
                // Push "stopping" visual state
                await reactiveState.set(State(productName: productName, status: .stopping))
                try await DeployerShell.Supervisor.stop(product: productName)

                // Push "starting" visual state
                await reactiveState.set(State(productName: productName, status: .starting))
                try await DeployerShell.Supervisor.start(product: productName)

                // Push the ground truth after startup completes
                let finalStatus = await DeployerShell.Supervisor.status(product: productName)
                await reactiveState.set(State(productName: productName, status: finalStatus))

                return .success()
            } catch {
                // On failure, query and push the actual state so the UI recovers
                let recoveryStatus = await DeployerShell.Supervisor.status(product: productName)
                await reactiveState.set(State(productName: productName, status: recoveryStatus))
                return .failure(message: error.localizedDescription)
            }
        }

    }

    /// Stop action: pushes a "stopping" visual state, executes the stop command,
    /// then lets the observe loop pick up the ground truth.
    struct StopAction: Mist.Action {

        let name = "stop"
        let productName: String
        let reactiveState: ReactiveState<State>

        func perform(id: UUID?, state: inout MistState, on db: Database) async -> ActionResult {
            do {
                // Push "stopping" visual state
                await reactiveState.set(State(productName: productName, status: .stopping))
                try await DeployerShell.Supervisor.stop(product: productName)

                // Push the ground truth after stop completes
                let finalStatus = await DeployerShell.Supervisor.status(product: productName)
                await reactiveState.set(State(productName: productName, status: finalStatus))

                return .success()
            } catch {
                let recoveryStatus = await DeployerShell.Supervisor.status(product: productName)
                await reactiveState.set(State(productName: productName, status: recoveryStatus))
                return .failure(message: error.localizedDescription)
            }
        }

    }

}
