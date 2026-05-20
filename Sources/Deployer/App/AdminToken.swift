import Foundation

/// Shared secret used by Bearer-token authentication on the `/admin` route group.
/// Read at server boot from `<installDir>/.deployer-admin.token`, generated if missing.
/// See `docs/adr/0005-cli-server-state-channel.md`.
struct AdminToken: Sendable {

    static let fileName = ".deployer-admin.token"

    let value: String

    /// Loads the token from the install directory. Generates and writes a fresh token if the file is absent.
    /// Returns `nil` if the file cannot be read or created — the admin route is then not mounted and CLI callers
    /// see 404 (treated as "refuse" rather than "proceed", per ADR 0005).
    static func loadOrGenerate(installDirectory: URL) -> AdminToken? {

        let fileURL = installDirectory.appendingPathComponent(fileName, isDirectory: false)
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: fileURL.path) {
            guard let data = try? Data(contentsOf: fileURL),
                  let raw = String(data: data, encoding: .utf8) else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return AdminToken(value: trimmed)
        }

        let token = generateHexToken(byteCount: 32)
        guard let data = token.data(using: .utf8) else { return nil }
        do {
            try data.write(to: fileURL, options: [.atomic])
            try fileManager.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: fileURL.path)
        } catch {
            return nil
        }

        return AdminToken(value: token)
    }

    private static func generateHexToken(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        for i in 0..<byteCount { bytes[i] = UInt8.random(in: .min ... .max) }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

}
