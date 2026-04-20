import Foundation

/// Setup-scoped shell helpers that execute commands as the service account with the runtime environment expected by managed processes.
enum SetupUserShell {

    /// Executes a command via `runuser` so privileged setup can perform filesystem and git operations as the target service identity.
    @discardableResult static func runAs(
        user: String,
        _ arguments: [String],
        directory: String? = nil,
        environment: [String: String]? = nil
    ) async throws -> String {

        let envArguments = (environment ?? [:])
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
        
        let command = envArguments.isEmpty
            ? ["runuser", "-u", user, "--"] + arguments
            : ["runuser", "-u", user, "--", "env"] + envArguments + arguments

        return try await Shell.runThrowing(command, directory: directory)
    }

    /// Same as `runAs` but streams tail output for long-running commands so build/install progress stays visible in setup output.
    @discardableResult static func runAsStreamingTail(
        user: String,
        _ arguments: [String],
        directory: String? = nil,
        environment: [String: String]? = nil
    ) async throws -> String {

        let envArguments = (environment ?? [:])
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
        
        let command = envArguments.isEmpty
            ? ["runuser", "-u", user, "--"] + arguments
            : ["runuser", "-u", user, "--", "env"] + envArguments + arguments

        return try await Shell.runStreamingTailThrowing(command, directory: directory)
    }

    /// Runs as the configured service user while enforcing `HOME` and `USER` so tool behavior matches non-root runtime expectations.
    @discardableResult static func runAsServiceUser(
        _ context: SetupContext,
        _ arguments: [String],
        directory: String? = nil,
        environment: [String: String]? = nil
    ) async throws -> String {

        let paths = try? context.requirePaths()
        let baseEnvironment = [
            "HOME": paths?.serviceHome ?? "/home/\(context.serviceUser)",
            "USER": context.serviceUser
        ]
        let mergedEnvironment = baseEnvironment.merging(environment ?? [:]) { _, new in new }
        return try await runAs(user: context.serviceUser, arguments, directory: directory, environment: mergedEnvironment)
    }

    /// Streaming variant of `runAsServiceUser` for long tasks where live progress is needed without sacrificing service-user environment defaults.
    @discardableResult static func runAsServiceUserStreamingTail(
        _ context: SetupContext,
        _ arguments: [String],
        directory: String? = nil,
        environment: [String: String]? = nil
    ) async throws -> String {

        let paths = try? context.requirePaths()
        let baseEnvironment = [
            "HOME": paths?.serviceHome ?? "/home/\(context.serviceUser)",
            "USER": context.serviceUser
        ]
        let mergedEnvironment = baseEnvironment.merging(environment ?? [:]) { _, new in new }
        return try await runAsStreamingTail(user: context.serviceUser, arguments, directory: directory, environment: mergedEnvironment)
    }

    /// Exposes the per-user runtime and DBus variables required for reliable `systemctl --user` calls outside interactive login sessions.
    static func systemdUserEnvironment(uid: Int) -> [String: String] {
        [
            "XDG_RUNTIME_DIR": "/run/user/\(uid)",
            "DBUS_SESSION_BUS_ADDRESS": "unix:path=/run/user/\(uid)/bus"
        ]
    }
    
    /// Runs `systemctl --user` against the setup service account by resolving UID-bound DBus runtime paths from collected setup state.
    @discardableResult static func runUserSystemctl(
        _ context: SetupContext,
        _ arguments: [String]
    ) async throws -> String {
        
        let uid = try await context.requireServiceUserUID()
        
        return try await runAsServiceUser(
            context,
            ["systemctl", "--user"] + arguments,
            environment: systemdUserEnvironment(uid: uid)
        )
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

}
