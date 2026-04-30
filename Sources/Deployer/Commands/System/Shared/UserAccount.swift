import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

enum UserAccount {

    /// Returns whether a passwd entry exists for the provided username.
    static func exists(_ user: String) async -> Bool {
        guard let cUser = user.cString(using: .utf8) else { return false }
        return getpwnam(cUser) != nil
    }

    /// Resolves a user's uid from the passwd database.
    static func uid(for user: String, errorLabel: String = "user") throws -> Int {
        guard let cUser = user.cString(using: .utf8), let entry = getpwnam(cUser) else {
            throw SystemError.invalidValue(errorLabel, "user '\(user)' does not exist")
        }

        let raw = entry.pointee.pw_uid
        return Int(raw)
    }

    /// Returns the effective uid of the current process.
    static func currentUID() -> Int {
        Int(geteuid())
    }

    /// Resolves the effective username of the current process.
    static func currentName() -> String? {
        guard let entry = getpwuid(geteuid()) else { return nil }
        return String(cString: entry.pointee.pw_name)
    }

    /// Resolves a user's home directory from the passwd database.
    static func homeDirectory(for user: String, errorLabel: String = "user") async throws -> String {
        guard let cUser = user.cString(using: .utf8), let entry = getpwnam(cUser) else {
            throw SystemError.invalidValue(errorLabel, "user '\(user)' does not exist")
        }

        return String(cString: entry.pointee.pw_dir)
    }

}
