import Vapor
import Foundation

/// Inserts a global `DenyUsers` directive into `/etc/ssh/sshd_config` for the service account.
struct SSHHardeningStep: SetupStep {

    let context: SetupContext
    let console: any Console

    let title = "SSH hardening (optional)"
    private let sshdConfigPath = "/etc/ssh/sshd_config"

    func run() async throws {

        let contents = try loadConfig()

        switch globalDenyStatus(in: contents) {
        case .covered:
            console.print("'\(context.serviceUser)' is already covered by a global DenyUsers directive. Skipping.")
            return
        case .scopedOnly:
            console.print("Warning: '\(context.serviceUser)' is denied in a Match block, but this may not apply globally.")
            console.print("Proceeding to insert a guaranteed global directive.")
        case .absent:
            break
        }

        console.print("This will insert 'DenyUsers \(context.serviceUser)' in global scope in \(sshdConfigPath).")

        guard console.confirm("Apply SSH hardening?", defaultYes: true) else {
            console.print("Skipped.")
            return
        }

        try await applyHardening(to: contents)
    }

}

extension SSHHardeningStep {

    enum DenyStatus {
        case covered
        case scopedOnly
        case absent
    }

    /// Parses config and reports whether `DenyUsers` is globally effective before the first `Match` block.
    private func globalDenyStatus(in contents: String) -> DenyStatus {
        
        let user = context.serviceUser.lowercased()
        var passedMatchBlock = false
        var foundInMatchBlock = false

        for raw in contents.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix("#"), !line.isEmpty else { continue }

            let tokens = line.split(whereSeparator: \.isWhitespace)
            guard let keyword = tokens.first?.lowercased() else { continue }

            if keyword == "match" {
                passedMatchBlock = true
                continue
            }

            if keyword == "denyusers" {
                let users = tokens.dropFirst().map { $0.lowercased() }
                if users.contains(user) {
                    if passedMatchBlock {
                        foundInMatchBlock = true
                    } else {
                        return .covered
                    }
                }
            }
        }

        return foundInMatchBlock ? .scopedOnly : .absent
    }

    /// Inserts the stanza before the first `Match` block, or appends it if no `Match` exists.
    private func writeDenyDirective(into contents: String) -> String {
        
        let stanza = "# Added by Vapor-Deployer setup — block inbound SSH for service account\nDenyUsers \(context.serviceUser)\n"
        var lines = contents.components(separatedBy: "\n")

        let matchIndex = lines.firstIndex { line in
            let tokens = line.split(whereSeparator: \.isWhitespace)
            let keyword = tokens.first?.lowercased()
            return keyword == "match"
        }

        if let matchIndex {
            lines.insert(contentsOf: ["", stanza], at: matchIndex)
            return lines.joined(separator: "\n")
        }

        return contents + "\n" + stanza
    }

    private func loadConfig() throws -> String {
        
        guard FileManager.default.fileExists(atPath: sshdConfigPath) else {
            throw SystemError.invalidValue(sshdConfigPath, "sshd_config not found")
        }
        
        return try String(contentsOfFile: sshdConfigPath, encoding: .utf8)
    }

    private func applyHardening(to contents: String) async throws {

        let backupPath = "\(sshdConfigPath).deployer-bak"

        try await Shell.runThrowing("cp", ["-a", sshdConfigPath, backupPath])

        do {
            let updated = writeDenyDirective(into: contents)
            try updated.write(toFile: sshdConfigPath, atomically: true, encoding: .utf8)

            let testResult = await Shell.run("sshd", ["-t"])
            guard testResult.exitCode == 0 else {
                throw SystemError.invalidValue(
                    sshdConfigPath,
                    "Validation failed after inserting DenyUsers:\n\(testResult.output.trimmed)"
                )
            }

            let reloadResult = await Shell.run("systemctl", ["reload", "sshd"])
            if reloadResult.exitCode != 0 {
                try await Shell.runThrowing("systemctl", ["reload", "ssh"])
            }

            console.print("SSH hardening applied. '\(context.serviceUser)' can no longer log in via SSH.")

            try? SystemFileSystem.removeIfPresent(backupPath)

        } catch {
            console.warning("SSH hardening failed. Reverting \(sshdConfigPath).")
            await Shell.run("mv", [backupPath, sshdConfigPath])
            throw error
        }
    }

}
