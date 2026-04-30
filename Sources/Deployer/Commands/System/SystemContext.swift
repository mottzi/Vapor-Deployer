import Foundation

/// Shared contract for host-level operations that need the service identity and path layout.
protocol SystemContext: AnyObject {
    
    var serviceUser: String { get }
    
    var serviceUserUID: Int? { get set }
    
    var paths: SystemPaths? { get }
    
}

extension SystemContext {

    /// Enforces that path layout has been derived before provisioning steps try to consume it.
    func requirePaths() throws -> SystemPaths {
        if let paths { return paths }
        throw SystemError.missingValue("paths")
    }

    /// Resolves and memoizes the service user's UID so user-scoped systemd calls can build runtime and DBus paths reliably.
    @discardableResult
    func requireServiceUserUID() async throws -> Int {

        if let serviceUserUID { return serviceUserUID }

        let intUID = try UserAccount.uid(for: serviceUser, errorLabel: "serviceUserUID")
        serviceUserUID = intUID
        return intUID
    }

}
