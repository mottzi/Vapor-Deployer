import Foundation

/// Abstracts setup-time and teardown-time service manager operations (writing configs, enabling/disabling, removing files).
///
/// Complements ``ServiceManager`` which covers runtime operations (start/stop/restart/status).
protocol ServiceConfigurator {

    /// Checks whether a named service is currently active.
    func isRunning(_ service: String) async -> Bool

    /// Stops services and prevents them from auto-restarting (best-effort).
    func disable(_ products: [String]) async

    /// Deletes config/unit files for the given products and reloads the daemon (best-effort).
    func removeConfigs(for products: [String]) async

    /// Enables services at boot and starts them.
    func enableAndStart(_ products: [String]) async throws

}

extension ServiceManagerKind {

    func makeConfigurator(shell: SystemShell, paths: SystemPaths) -> any ServiceConfigurator {
        switch self {
        case .systemd: SystemdConfigurator(shell: shell, paths: paths)
        case .supervisor: SupervisorConfigurator()
        }
    }

}
