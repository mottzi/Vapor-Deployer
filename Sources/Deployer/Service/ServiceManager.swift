import Vapor

extension Deployer {
    
    var serviceManager: any ServiceManager {
        get {
            if let manager = app.storage[DeployerServiceManagerKey.self] { return manager }
            fatalError("Service manager not initialized.")
        }
        nonmutating set {
            app.storage[DeployerServiceManagerKey.self] = newValue
        }
    }
    
    private struct DeployerServiceManagerKey: StorageKey {
        typealias Value = any ServiceManager
    }
    
}

/// A common interface for controlling and querying the lifecycle of a deployed application.
protocol ServiceManager: Sendable {
    
    func start(product: String) async throws
    func restart(product: String) async throws
    func stop(product: String) async throws
    
    func status(product: String) async -> ServiceStatus
    func isRunning(product: String) async -> Bool
    
}

extension ServiceManager {
    
    func isRunning(product: String) async -> Bool {
        let currentStatus = await status(product: product)
        return currentStatus.isRunning
    }
    
}

/// Represents the normalized state of a managed service, abstracting away the underlying service manager.
enum ServiceStatus: String {
    
    case starting  = "STARTING"
    case running   = "RUNNING"
    case backoff   = "BACKOFF"
    case stopping  = "STOPPING"
    case stopped   = "STOPPED"
    case exited    = "EXITED"
    case fatal     = "FATAL"
    case unknown   = "UNKNOWN"

    var label: String { rawValue.lowercased() }
    
    var isRunning: Bool { self == .running }
    var isTransitioning: Bool { self == .starting || self == .stopping }
    
}
