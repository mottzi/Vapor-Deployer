import Foundation

/// The host service backend used to control and provision managed services.
enum ServiceBackend: String, Codable {
    
    /// Comes preinstalled with Ubuntu.
    case systemd
    
    /// Is easier to use than systemd but requires dependency.
    case supervisor
    
}

extension ServiceBackend {
    
    /// Creates a service manager instance for this backend.
    func makeManager(serviceUser: String? = nil) throws -> any ServiceManager {
        
        switch self {
            case .systemd:
                guard let user = serviceUser?.trimmed, !user.isEmpty else {
                    throw Host.Error.missingValue("serviceUser")
                }
                return SystemdServiceManager(serviceUser: user)
                    
            case .supervisor:
                return SupervisorServiceManager()
        }
    }

    /// Creates a service configurator instance for this backend.
    func makeConfigurator(shell: ProvisioningShell, paths: ProvisioningPaths) -> any ServiceConfigurator {
        switch self {
            case .systemd: SystemdConfigurator(shell: shell, paths: paths)
            case .supervisor: SupervisorConfigurator()
        }
    }
    
}
