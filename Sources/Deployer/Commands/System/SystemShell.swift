import Foundation

// Shell facade for setup and remove steps; instance methods use SystemContext, static members provide lower-level commands.
struct SystemShell {
    
    let context: any SystemContext

    /// Runs as the configured service user while enforcing `HOME` and `USER` so tool behavior matches non-root runtime expectations.
    @discardableResult
    func runAsServiceUser(
        _ command: String,
        _ arguments: [String] = [],
        directory: String? = nil,
        environment: [String: String]? = nil
    ) async throws -> String {
        
        try await SystemShell.runAs(
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
        
        try await SystemShell.runAsStreamingTail(
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

        try await SystemShell.runUserSystemctl(
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

extension SystemShell {

    /// Ensures a command runs as the target user, avoiding nested `runuser` when already in that identity.
    @discardableResult
    static func runAs(
        user: String,
        _ command: String,
        _ arguments: [String] = [],
        directory: String? = nil,
        environment: [String: String]? = nil
    ) async throws -> String {

        if shouldRunDirectly(as: user) {
            return try await Shell.runThrowing(
                command,
                arguments,
                directory: directory,
                environment: environment
            )
        }

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

        if shouldRunDirectly(as: user) {
            return try await Shell.runStreamingTail(
                command,
                arguments,
                directory: directory,
                environment: environment
            )
        }

        let runuser = runuserCommand(user: user, command: command, arguments: arguments, environment: environment)
        return try await Shell.runStreamingTail(
            runuser.command,
            runuser.arguments,
            directory: directory
        )
    }

    /// Runs `systemctl --user` in the service-user identity with the required DBus runtime environment.
    @discardableResult
    static func runUserSystemctl(
        user: String,
        uid: Int,
        command: String,
        arguments: [String] = []
    ) async throws -> String {

        let argv = ["--user", command] + arguments
        return try await runAs(
            user: user,
            "systemctl",
            argv,
            environment: systemdUserEnvironment(uid: uid)
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

        throw SystemError.serviceTimeout("user@\(uid).service bus")
    }
}

extension SystemShell {

    private static func shouldRunDirectly(as user: String) -> Bool {
        if UserAccount.currentUID() == 0 { return false }
        guard let currentUser = UserAccount.currentName() else { return false }
        return currentUser == user
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
