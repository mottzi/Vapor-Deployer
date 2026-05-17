import Vapor
import Mist

extension Deployer {

    func useQueue(
        config: Configuration,
        deployerState: LiveState<DeployerState>,
        onStatusChange: @escaping @Sendable (ServiceStatus) async -> Void
    ) {
        queue = Queue(app: app, config: config, deployerState: deployerState, onStatusChange: onStatusChange)
    }

    var queue: Queue {
        get {
            if let queue = app.storage[QueueKey.self] { return queue }
            fatalError("Queue not initialized.")
        }
        nonmutating set {
            app.storage[QueueKey.self] = newValue
        }
    }

    private struct QueueKey: StorageKey { typealias Value = Queue }

}
