import Foundation

// Shell facade for setup steps; instance methods use SetupContext, static members provide lower-level commands.
struct SetupShell {
    
    let context: SetupContext
        
    /// Runs as the configured service user while enforcing `HOME` and `USER` so tool behavior matches non-root runtime expectations.
    @discardableResult
    func runAsServiceUser(
        _ command: String,
        _ arguments: [String] = [],
        directory: String? = nil,
        environment: [String: String]? = nil
    ) async throws -> String {
        
        try await SetupShell.runAs(
            user: context.serviceUser,
            command,
            arguments,
            directory: directory,
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
        
        try await SetupShell.runAsStreamingTail(
            user: context.serviceUser,
            command,
            arguments,
            directory: directory,
            environment: serviceUserEnvironment(merging: environment)
        )
    }
    
    /// Runs `systemctl --user` against the setup service account by resolving UID-bound DBus runtime paths from collected setup state.
    @discardableResult
    func runUserSystemctl(_ command: String, _ arguments: [String] = []) async throws -> String {
        
        try await runAsServiceUser(
            "systemctl --user \(command)",
            arguments,
            environment: SetupShell.systemdUserEnvironment(uid: try await context.requireServiceUserUID())
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
        _ command: String,
        _ arguments: [String] = [],
        directory: String? = nil,
        environment: [String: String]? = nil
    ) async throws -> String {

        let runuser = runuserCommand(user: user, command: command, arguments: arguments, environment: environment)
        return try await Shell.runThrowing(
            runuser.command,
            runuser.arguments,
            directory: directory
        )
    }

    /// Streaming variant of `runAs` for long-running commands so build/install progress stays visible in setup output.
    @discardableResult
    static func runAsStreamingTail(
        user: String,
        _ command: String,
        _ arguments: [String] = [],
        directory: String? = nil,
        environment: [String: String]? = nil
    ) async throws -> String {

        let runuser = runuserCommand(user: user, command: command, arguments: arguments, environment: environment)
        return try await Shell.runStreamingTailThrowing(
            runuser.command,
            runuser.arguments,
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
        command: String,
        arguments: [String],
        environment: [String: String]?
    ) -> (command: String, arguments: [String]) {

        let envArguments = (environment ?? [:])
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }

        let userArgv = Shell.tokenize(command) + arguments
        let runuserArgs = envArguments.isEmpty
            ? ["-u", user, "--"] + userArgv
            : ["-u", user, "--", "env"] + envArguments + userArgv
        return ("runuser", runuserArgs)
    }

}
