import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Musl)
import Musl
#elseif canImport(Glibc)
import Glibc
#endif

/// Host-level process and Linux/macOS account helpers shared by setup, teardown, services, and runtime boot.
enum Host {

    /// Reads local OS account records so provisioning can validate the managed service identity consistently.
    enum User {

        /// Distinguishes direct root installs from helper-mediated refreshes without trusting launch arguments.
        static var currentUID: Int {
            Int(geteuid())
        }

        /// Provides the runtime service owner when bootstrapping service managers outside setup context.
        static var currentName: String? {
            guard let entry = getpwuid(geteuid()) else { return nil }
            return String(cString: entry.pointee.pw_name)
        }

        /// Lets setup/remove decide whether service-account work should create, reuse, or skip cleanup.
        static func exists(_ user: String) async -> Bool {
            guard let cUser = user.cString(using: .utf8) else { return false }
            return getpwnam(cUser) != nil
        }

        /// Converts the service account to the numeric identity required by user-scoped systemd and DBus paths.
        static func uid(for user: String, errorLabel: String = "user") throws -> Int {
            
            guard let cUser = user.cString(using: .utf8),
                  let entry = getpwnam(cUser)
            else { throw Host.Error.invalidValue(errorLabel, "user '\(user)' does not exist") }

            return Int(entry.pointee.pw_uid)
        }
        
        /// Verifies an existing service account points at the install home before setup reuses it.
        static func homeDirectory(for user: String, errorLabel: String = "user") async throws -> String {
            
            guard let cUser = user.cString(using: .utf8),
                  let entry = getpwnam(cUser)
            else { throw Host.Error.invalidValue(errorLabel, "user '\(user)' does not exist") }

            return String(cString: entry.pointee.pw_dir)
        }

    }

}
