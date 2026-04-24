import Foundation

/// Shared helpers for resolving Linux user-account metadata via `getent`, keeping setup, remove, and `deployerctl` on a single lookup path.
enum UserAccount {

    /// Resolves a user's home directory by parsing `getent passwd <user>`, throwing a `SystemError.invalidValue` labelled with `errorLabel` on malformed output.
    static func homeDirectory(for user: String, errorLabel: String = "user") async throws -> String {

        let passwd = try await Shell.runThrowing("getent", ["passwd", user]).trimmed
        let fields = passwd.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        if fields.count >= 6 { return fields[5] }

        throw SystemError.invalidValue(errorLabel, "getent passwd for '\(user)' returned malformed output")
    }

}
