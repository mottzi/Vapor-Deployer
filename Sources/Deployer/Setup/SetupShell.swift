import Foundation

/// Shell facade used by setup steps. Instance methods run commands against the
/// configured service account using the bound `SetupContext`, while `static`
/// members expose the lower-level primitives that don't depend on context.
struct SetupShell {
    
    let context: SetupContext
        
    /// Runs as the configured service user while enforcing `HOME` and `USER` so tool behavior matches non-root runtime expectations.
    @discardableResult
    func runAsServiceUser(
        _ arguments: [String],
        directory: String? = nil,
        environment: [String: String]? = nil
    ) async throws -> String {
        
        let mergedEnvironment = serviceUserEnvironment(merging: environment)
        return try await SetupShell.runAs(
            user: context.serviceUser,
            arguments,
            directory: directory,
            environment: mergedEnvironment
        )
    }
    
    /// Streaming variant of `runAsServiceUser` for long tasks where live progress is needed without sacrificing service-user environment defaults.
    @discardableResult
    func runAsServiceUserStreamingTail(
        _ arguments: [String],
        directory: String? = nil,
        environment: [String: String]? = nil
    ) async throws -> String {
        
        let mergedEnvironment = serviceUserEnvironment(merging: environment)
        return try await SetupShell.runAsStreamingTail(
            user: context.serviceUser,
            arguments,
            directory: directory,
            environment: mergedEnvironment
        )
    }
    
    /// Runs `systemctl --user` against the setup service account by resolving UID-bound DBus runtime paths from collected setup state.
    @discardableResult
    func runUserSystemctl(_ arguments: [String]) async throws -> String {
        
        let uid = try await context.requireServiceUserUID()
        return try await runAsServiceUser(
            ["systemctl", "--user"] + arguments,
            environment: SetupShell.systemdUserEnvironment(uid: uid)
        )
    }
    
    private func serviceUserEnvironment(merging overrides: [String: String]?) -> [String: String] {
        let paths = try? context.requirePaths()
        let base = [
            "HOME": paths?.serviceHome ?? "/home/\(context.serviceUser)",
            "USER": context.serviceUser
        ]
        return base.merging(overrides ?? [:]) { _, new in new }
    }
    
}

extension SetupShell {

    /// Executes a command via `runuser` so privileged setup can perform filesystem and git operations as the target service identity.
    @discardableResult
    static func runAs(
        user: String,
        _ arguments: [String],
        directory: String? = nil,
        environment: [String: String]? = nil
    ) async throws -> String {

        return try await Shell.runThrowing(
            runuserCommand(user: user, arguments: arguments, environment: environment),
            directory: directory
        )
    }

    /// Streaming variant of `runAs` for long-running commands so build/install progress stays visible in setup output.
    @discardableResult
    static func runAsStreamingTail(
        user: String,
        _ arguments: [String],
        directory: String? = nil,
        environment: [String: String]? = nil
    ) async throws -> String {

        return try await Shell.runStreamingTailThrowing(
            runuserCommand(user: user, arguments: arguments, environment: environment),
            directory: directory
        )
    }

    /// Exposes the per-user runtime and DBus variables required for reliable `systemctl --user` calls outside interactive login sessions.
    static func systemdUserEnvironment(uid: Int) -> [String: String] {
        [
            "XDG_RUNTIME_DIR": "/run/user/\(uid)",
            "DBUS_SESSION_BUS_ADDRESS": "unix:path=/run/user/\(uid)/bus"
        ]
    }

    /// Waits for the user systemd bus socket so service operations do not race startup of `user@<uid>.service`.
    static func waitForUserBus(uid: Int, timeout: Duration = .seconds(5)) async throws {

        let busPath = "/run/user/\(uid)/bus"
        let start = ContinuousClock.now

        while start.duration(to: ContinuousClock.now) < timeout {
            if FileManager.default.fileExists(atPath: busPath) { return }
            try await Task.sleep(for: .milliseconds(100))
        }

        throw SetupCommand.Error.serviceTimeout("user@\(uid).service bus")
    }

    private static func runuserCommand(
        user: String,
        arguments: [String],
        environment: [String: String]?
    ) -> [String] {

        let envArguments = (environment ?? [:])
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }

        return envArguments.isEmpty
            ? ["runuser", "-u", user, "--"] + arguments
            : ["runuser", "-u", user, "--", "env"] + envArguments + arguments
    }

}
