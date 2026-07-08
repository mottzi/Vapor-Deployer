import Foundation

/// Shell facade for setup and remove steps; instance methods use ProvisioningContext.
struct ProvisioningShell {
    
    let context: any ProvisioningContext

    /// Runs as the configured service user while enforcing `HOME` and `USER` so tool behavior matches non-root runtime expectations.
    @discardableResult
    func runAsServiceUser(
        _ command: String,
        _ arguments: [String] = [],
        directory: String? = nil,
        environment: [String: String]? = nil
    ) async throws -> String {
        
        try await Host.Command.runAs(
            user: context.serviceUser,
            command,
            arguments,
            directory: directory ?? serviceUserHomeDirectory,
            environment: serviceUserEnvironment(merging: environment)
        )
    }
    
    /// Streaming variant of `runAsServiceUser` for long tasks where live progress is needed without sacrificing service-user environment defaults.
    @discardableResult
    func runAsServiceUserStreamingTail(
        _ command: String,
        _ arguments: [String] = [],
        directory: String? = nil,
        environment: [String: String]? = nil
    ) async throws -> String {
        
        try await Host.Command.runAsStreamingTail(
            user: context.serviceUser,
            command,
            arguments,
            directory: directory ?? serviceUserHomeDirectory,
            environment: serviceUserEnvironment(merging: environment)
        )
    }
    
    /// Runs `systemctl --user` against the setup service account with the same identity policy used by runtime service operations.
    @discardableResult
    func runUserSystemctl(_ command: String, _ arguments: [String] = []) async throws -> String {

        try await Host.Command.runUserSystemctl(
            user: context.serviceUser,
            uid: try await context.requireServiceUserUID(),
            command: command,
            arguments: arguments
        )
    }
    
    /// Runs a `git` subcommand as the service user, optionally scoped to a working copy via `-C`.
    @discardableResult
    func git(
        _ subcommand: String,
        _ arguments: [String] = [],
        in directory: String? = nil,
        environment: [String: String]? = nil
    ) async throws -> String {
        
        let scope = directory.map { ["-C", $0] } ?? []
        return try await runAsServiceUser("git", scope + [subcommand] + arguments, environment: environment)
    }

}

extension ProvisioningShell {

    private func serviceUserEnvironment(merging overrides: [String: String]?) -> [String: String] {
        let base = [
            "HOME": serviceUserHomeDirectory,
            "USER": context.serviceUser
        ]
        return base.merging(overrides ?? [:]) { _, new in new }
    }

    private var serviceUserHomeDirectory: String {
        (try? context.requirePaths().serviceHome) ?? "/home/\(context.serviceUser)"
    }

}
