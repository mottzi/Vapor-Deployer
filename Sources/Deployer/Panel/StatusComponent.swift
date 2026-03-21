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

    public struct State: Encodable, Equatable, Sendable {
        public let productName: String
        public let status: String
        public let isRunning: Bool
        public let isTransitioning: Bool

        /// Internal convenience initializer that maps from the Supervisor.Status enum.
        init(productName: String, status: DeployerShell.Supervisor.Status) {
            self.productName = productName
            self.status = status.label
            self.isRunning = status.isRunning
            self.isTransitioning = status.isTransitioning
        }
    }

    // MARK: - Background Observation

    public func observe(app: Application) async {

        let initialStatus = await DeployerShell.Supervisor.status(product: productName)
        await reactiveState.set(State(productName: productName, status: initialStatus))

        while !app.didShutdown && !Task.isCancelled {

            try? await Task.sleep(for: interval)
            guard !app.didShutdown && !Task.isCancelled else { break }

            guard await !shouldPause(on: app) else { continue }

            let currentStatus = await DeployerShell.Supervisor.status(product: productName)
            await reactiveState.set(State(productName: productName, status: currentStatus))
        }
    }

}

// MARK: - Actions

extension StatusComponent {

    struct RestartAction: Mist.Action {

        let name = "restart"
        let productName: String
        let reactiveState: ReactiveState<State>

        func perform(id: UUID?, state: inout MistState, on db: Database) async -> ActionResult {
            do {
                await reactiveState.set(State(productName: productName, status: .stopping))
                try await DeployerShell.Supervisor.stop(product: productName)

                await reactiveState.set(State(productName: productName, status: .starting))
                try await DeployerShell.Supervisor.start(product: productName)

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

    struct StopAction: Mist.Action {

        let name = "stop"
        let productName: String
        let reactiveState: ReactiveState<State>

        func perform(id: UUID?, state: inout MistState, on db: Database) async -> ActionResult {
            do {
                await reactiveState.set(State(productName: productName, status: .stopping))
                try await DeployerShell.Supervisor.stop(product: productName)

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
