import Foundation
import Vapor

/// A common interface for controlling and querying the lifecycle of a deployed application.
protocol DeployerServiceManager: Sendable {
    
    func start(product: String) async throws
    func restart(product: String) async throws
    func stop(product: String) async throws
    
    func status(product: String) async -> DeployerServiceStatus
    func isRunning(product: String) async -> Bool
    
}

extension DeployerServiceManager {
    
    func isRunning(product: String) async -> Bool {
        let currentStatus = await status(product: product)
        return currentStatus.isRunning
    }
    
}

/// Represents the normalized state of a managed service, abstracting away the underlying service manager.
enum DeployerServiceStatus: String {
    
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

/// A service manager implementation that delegates to `supervisorctl`.
struct SupervisorServiceManager: DeployerServiceManager {

    func start(product: String) async throws {
        try await DeployerShell.execute("supervisorctl start \(product)")
    }

    func restart(product: String) async throws {
        try await DeployerShell.execute("supervisorctl restart \(product)")
    }

    func stop(product: String) async throws {
        try await DeployerShell.execute("supervisorctl stop \(product)")
    }

    func status(product: String) async -> DeployerServiceStatus {

        let output = await DeployerShell.executeRaw("supervisorctl status \(product)")
        let arguments = output.split(whereSeparator: { $0.isWhitespace })
        guard let stateToken = arguments.dropFirst().first else { return .unknown }
        let stateString = String(stateToken)
        
        return DeployerServiceStatus(rawValue: stateString) ?? .unknown
    }

}

/// A service manager implementation that delegates to `systemctl`.
struct SystemdServiceManager: DeployerServiceManager {

    func start(product: String) async throws {
        try await DeployerShell.execute("\(prefix) systemctl --user start \(product).service")
    }

    func restart(product: String) async throws {
        try await DeployerShell.execute("\(prefix) systemctl --user restart \(product).service")
    }

    func stop(product: String) async throws {
        try await DeployerShell.execute("\(prefix) systemctl --user stop \(product).service")
    }

    func status(product: String) async -> DeployerServiceStatus {
        
        let output = await DeployerShell.executeRaw("\(prefix) systemctl --user is-active \(product).service")
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return switch trimmed {
            case "active": .running
            case "activating": .starting
            case "deactivating": .stopping
            case "inactive": .stopped
            case "failed": .fatal
            default: .unknown
        }
    }
    
    /// Prefix needed so `systemctl --user` can connect from non-login service contexts.
    private let prefix = "XDG_RUNTIME_DIR=/run/user/$(id -u)"

}

extension Deployer {
    
    var serviceManager: any DeployerServiceManager {
        get {
            if let manager = app.storage[DeployerServiceManagerKey.self] { return manager }
            fatalError("Service manager not initialized.")
        }
        nonmutating set {
            app.storage[DeployerServiceManagerKey.self] = newValue
        }
    }
    
    private struct DeployerServiceManagerKey: StorageKey {
        typealias Value = any DeployerServiceManager
    }
    
}
