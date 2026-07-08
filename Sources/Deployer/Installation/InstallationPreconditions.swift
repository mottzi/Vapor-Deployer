import Foundation

/// Preconditions for commands that install, update, or remove host-managed deployer resources.
enum InstallationPreconditions {

    /// Ensures privileged filesystem and service-management operations cannot fail midway under an unprivileged user.
    static func requireRoot() throws {
        guard geteuid() == 0 else { throw Host.Error.notRoot }
    }

    /// Guards distro-specific provisioning (`apt`, `systemd`, Certbot paths) that assumes Ubuntu naming and layout.
    static func requireUbuntu() throws {

        let releaseFileText =
            (try? String(contentsOfFile: "/etc/os-release", encoding: .utf8)) ?? ""

        let lines = releaseFileText.split(whereSeparator: \.isNewline)
        let line = lines.first(where: { $0.hasPrefix("ID=") })
        let osRaw = line?.dropFirst("ID=".count) ?? "unknown"
        let os = String(osRaw).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))

        guard os == "ubuntu" else { throw Host.Error.unsupportedOperatingSystem(os) }
    }

}
