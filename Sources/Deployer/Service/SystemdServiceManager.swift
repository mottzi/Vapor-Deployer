import Foundation

/// A service manager implementation that delegates to `systemctl`.
struct SystemdServiceManager: ServiceManager {

    func start(product: String) async throws {
        try await Shell.execute("\(prefix) systemctl --user start \(product).service")
    }

    func restart(product: String) async throws {
        try await Shell.execute("\(prefix) systemctl --user restart \(product).service")
    }

    func stop(product: String) async throws {
        try await Shell.execute("\(prefix) systemctl --user stop \(product).service")
    }

    func status(product: String) async -> ServiceStatus {
        
        let output = await Shell.executeRaw("\(prefix) systemctl --user is-active \(product).service")
        let trimmed = output.trimmed
        
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
