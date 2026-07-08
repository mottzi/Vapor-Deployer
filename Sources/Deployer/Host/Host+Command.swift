import Foundation
import Logging

extension Host {

    /// Arbitrates privilege transitions and user-scoped systemd DBus configurations across installation and run-time update phases.
    enum Command {
    
        private static let logger = Logger(label: "codes.mottzi.deployer.host")

        @discardableResult
        /// Ensures a command runs as the target user, avoiding nested `runuser` when already in that identity.
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

        @discardableResult
        /// Streaming variant of `runAs` for long-running commands so build/install progress stays visible in setup output.
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

        @discardableResult
        /// Runs `systemctl --user` in the service-user identity with the required DBus runtime environment.
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
        
            logger.info("Waiting for systemd user bus socket (UID: \(uid))...")

            while start.duration(to: ContinuousClock.now) < timeout {
                if FileManager.default.fileExists(atPath: busPath) { return }
                try await Task.sleep(for: .milliseconds(100))
            }

            throw Host.Error.serviceTimeout("user@\(uid).service bus")
        }

    }

}

extension Host.Command {
    
    /// Bypasses runuser isolation only if the current process is not root and matches the target user identity.
    private static func shouldRunDirectly(as user: String) -> Bool {
        if Host.User.currentUID == 0 { return false }
        guard let currentUser = Host.User.currentName else { return false }
        return currentUser == user
    }

    /// Packages environmental variables and tokenized commands into a `runuser` wrapper to downgrade host privileges safely.
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
