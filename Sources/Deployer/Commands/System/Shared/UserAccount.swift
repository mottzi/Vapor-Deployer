import Foundation

enum UserAccount {

    /// Returns whether `id -u <user>` succeeds.
    static func exists(_ user: String) async -> Bool {
        await Shell.run("id", ["-u", user]).exitCode == 0
    }

    /// Resolves a user's home directory by parsing `getent passwd <user>`.
    static func homeDirectory(for user: String, errorLabel: String = "user") async throws -> String {

        let passwd = try await Shell.runThrowing("getent", ["passwd", user]).trimmed
        let fields = passwd.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        if fields.count >= 6 { return fields[5] }

        throw SystemError.invalidValue(errorLabel, "getent passwd for '\(user)' returned malformed output")
    }

}
