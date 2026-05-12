import Foundation

/// The underlying service manager used to control the deployed application.
enum ServiceManagerKind: String, Codable, Sendable {
    
    /// Comes preinstalled with Ubuntu.
    case systemd
    
    /// Is easier to use than systemd but requires dependency.
    case supervisor
    
    /// Creates a service manager instance of the specified kind.
    func makeManager(serviceUser: String? = nil) throws -> any ServiceManager {
        
        switch self {
        case .systemd:
            guard let user = serviceUser?.trimmed, !user.isEmpty else {
                throw SystemError.missingValue("serviceUser")
            }
            return SystemdServiceManager(serviceUser: user)
                
        case .supervisor:
            return SupervisorServiceManager()
        }
    }
    
}
