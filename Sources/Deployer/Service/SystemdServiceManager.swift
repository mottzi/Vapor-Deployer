import Foundation

/// A service manager implementation that delegates to `systemctl`.
struct SystemdServiceManager: ServiceManager {

    let serviceUser: String?

    func start(product: String) async throws {
        try await Shell.runThrowing("\(prefix) systemctl --user start \(product).service")
    }

    func restart(product: String) async throws {
        try await Shell.runThrowing("\(prefix) systemctl --user restart \(product).service")
    }

    func stop(product: String) async throws {
        try await Shell.runThrowing("\(prefix) systemctl --user stop \(product).service")
    }

    func status(product: String) async -> ServiceStatus {
        
        let output = await Shell.run("\(prefix) systemctl --user is-active \(product).service").output
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
    var prefix: String {
        guard let serviceUser = normalizedServiceUser else {
            return "XDG_RUNTIME_DIR=/run/user/$(id -u)"
        }
        
        let user = serviceUser.shellQuoted
        let runtimeDir = "/run/user/$(id -u \(user))"
        return "XDG_RUNTIME_DIR=\(runtimeDir) DBUS_SESSION_BUS_ADDRESS=unix:path=\(runtimeDir)/bus"
    }

    private var normalizedServiceUser: String? {
        let trimmed = serviceUser?.trimmed ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

}
