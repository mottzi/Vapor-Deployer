import Foundation

/// Shared contract for installation operations that need the service identity and path layout.
protocol InstallationContext: AnyObject {
    
    var serviceUser: String { get }
    
    var serviceUserUID: Int? { get set }
    
    var paths: InstallationPaths? { get }
    
}

extension InstallationContext {

    /// Enforces that path layout has been derived before provisioning steps try to consume it.
    func requirePaths() throws -> InstallationPaths {
        if let paths { return paths }
        throw Host.Error.missingValue("paths")
    }

    /// Resolves and memoizes the service user's UID so user-scoped systemd calls can build runtime and DBus paths reliably.
    @discardableResult
    func requireServiceUserUID() async throws -> Int {

        if let serviceUserUID { return serviceUserUID }

        let intUID = try Host.User.uid(for: serviceUser, errorLabel: "serviceUserUID")
        serviceUserUID = intUID
        return intUID
    }

}
