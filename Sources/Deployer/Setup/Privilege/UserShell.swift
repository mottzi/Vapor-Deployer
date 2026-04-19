import Foundation

enum UserShell {

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

    static func systemdUserEnvironment(uid: Int) -> [String: String] {
        [
            "XDG_RUNTIME_DIR": "/run/user/\(uid)",
            "DBUS_SESSION_BUS_ADDRESS": "unix:path=/run/user/\(uid)/bus"
        ]
    }

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
