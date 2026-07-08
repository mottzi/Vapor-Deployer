import Foundation

/// Shared contract for setup/remove state that needs service identity and the derived host layout.
protocol ProvisioningContext: AnyObject {
    
    var serviceUser: String { get }
    
    var serviceUserUID: Int? { get set }
    
    var paths: ProvisioningPaths? { get }
    
}

extension ProvisioningContext {

    /// Enforces that path layout has been derived before provisioning steps try to consume it.
    func requirePaths() throws -> ProvisioningPaths {
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
