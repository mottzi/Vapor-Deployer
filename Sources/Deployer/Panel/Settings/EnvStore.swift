import Foundation

/// Reads and writes the target app's `.env` file. The file is the source of truth — the deployer
/// renders it on save and the running Vapor app reads it at boot via `DotEnvFile.load()` against its
/// working directory. See ADR 0008 for the rationale.
struct EnvStore {

    /// Absolute path to the target's `.env`, e.g. `/home/vapor/apps/<appName>/.env`.
    let envFilePath: String

    /// A single environment variable entry as it appears in the form / file.
    struct Entry: Equatable, Sendable {
        let key: String
        let value: String
    }

    /// Validation problem attached to a specific row index (or to the whole form when `rowIndex` is nil).
    struct ValidationIssue: Equatable, Sendable {
        let rowIndex: Int?
        let message: String
    }

    enum LoadError: Swift.Error { case readFailed(String, underlying: Swift.Error) }
    enum SaveError: Swift.Error {
        case validation([ValidationIssue])
        case writeFailed(String, underlying: Swift.Error)
    }

}

extension EnvStore {

    /// Returns the current entries, or an empty array if the file does not exist yet. Lines we cannot
    /// parse are skipped silently — the file is round-tripped through the UI from now on, so a single
    /// pass of "load → save" will normalize any pre-existing formatting drift.
    func load() throws -> [Entry] {

        let url = URL(fileURLWithPath: envFilePath)
        let raw: String
        do {
            raw = try String(contentsOf: url, encoding: .utf8)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return []
        } catch {
            throw LoadError.readFailed(envFilePath, underlying: error)
        }

        return EnvStore.parse(raw)
    }

    /// Validates entries, renders the canonical file, and writes it atomically with mode 0600.
    /// Throws `SaveError.validation` with every problem at once so the UI can show them all in one pass.
    func save(_ entries: [Entry]) throws {

        let issues = EnvStore.validate(entries)
        guard issues.isEmpty else { throw SaveError.validation(issues) }

        let rendered = EnvStore.render(entries)
        guard let data = rendered.data(using: .utf8) else {
            throw SaveError.validation([ValidationIssue(rowIndex: nil, message: "Failed to encode UTF-8")])
        }
        guard data.count <= EnvStore.maxFileBytes else {
            throw SaveError.validation([ValidationIssue(
                rowIndex: nil,
                message: "File would be \(data.count) bytes; maximum is \(EnvStore.maxFileBytes)."
            )])
        }

        let url = URL(fileURLWithPath: envFilePath)
        do {
            try data.write(to: url, options: [.atomic])
        } catch {
            throw SaveError.writeFailed(envFilePath, underlying: error)
        }

        // Tighten permissions to 0600. `Data.write(.atomic)` on the first creation respects the
        // process umask, which on a typical service install is 0022 — leaving the file world-readable.
        // The chmod runs on every save to make the invariant idempotent.
        try? FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: envFilePath
        )
    }

}

extension EnvStore {

    /// Maximum byte size for the rendered file. A sanity bound, not a security limit.
    static let maxFileBytes = 64 * 1024
    /// Maximum key length. POSIX permits longer but anything legitimate is well under this.
    static let maxKeyLength = 128
    /// Maximum value length. Single-line tokens (URLs, JWTs, base64 secrets) fit comfortably under 4 KB.
    static let maxValueLength = 4096
    /// Keys reserved by the service manager (systemd / supervisor sets them in the unit).
    /// Allowing the user to override these via `.env` would either be silently ignored or confusing.
    static let reservedKeys: Set<String> = ["PATH", "HOME", "USER"]
    /// POSIX env-var name: leading letter or underscore, then letters / digits / underscores.
    private static let keyPattern = #"^[A-Z_][A-Z0-9_]*$"#

    /// Returns one `ValidationIssue` per problem found. Empty result means the input is safe to render.
    static func validate(_ entries: [Entry]) -> [ValidationIssue] {

        var issues: [ValidationIssue] = []
        var seen: Set<String> = []

        for (index, entry) in entries.enumerated() {

            let key = entry.key
            if key.isEmpty {
                issues.append(.init(rowIndex: index, message: "Key is required."))
            } else if key.count > maxKeyLength {
                issues.append(.init(rowIndex: index, message: "Key must be \(maxKeyLength) characters or fewer."))
            } else if key.range(of: keyPattern, options: .regularExpression) == nil {
                issues.append(.init(rowIndex: index, message: "Key must match [A-Z_][A-Z0-9_]* (uppercase, digits, underscores; leading letter or underscore)."))
            } else if reservedKeys.contains(key) {
                issues.append(.init(rowIndex: index, message: "\(key) is set by the service manager and cannot be overridden here."))
            } else if !seen.insert(key).inserted {
                issues.append(.init(rowIndex: index, message: "Duplicate key \(key)."))
            }

            let value = entry.value
            if value.count > maxValueLength {
                issues.append(.init(rowIndex: index, message: "Value must be \(maxValueLength) characters or fewer."))
            }
            if value.contains("\n") || value.contains("\r") {
                issues.append(.init(rowIndex: index, message: "Value cannot contain newlines."))
            }
        }

        return issues
    }

    /// Renders entries as a canonical `.env`. Values are single-quoted with `'\''` escaping — the
    /// bulletproof POSIX-shell encoding that both Vapor's `DotEnvFile` and `set -a; .` accept.
    static func render(_ entries: [Entry]) -> String {

        var lines: [String] = ["# Managed by Vapor Deployer. Edits made by hand may be overwritten."]
        for entry in entries {
            lines.append("\(entry.key)=\(singleQuoteEscape(entry.value))")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Wraps a value in single quotes, escaping embedded single quotes as `'\''` (close, escaped-quote, open).
    private static func singleQuoteEscape(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    /// Lenient line-oriented parser. Recognizes `KEY=VALUE` with optional surrounding single or double
    /// quotes. Skips blank lines and `#`-prefixed comments. Anything malformed is silently dropped —
    /// the next save normalizes the file back to canonical form.
    static func parse(_ raw: String) -> [Entry] {

        var entries: [Entry] = []
        for rawLine in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }

            guard let equalsIndex = line.firstIndex(of: "=") else { continue }
            let key = String(line[line.startIndex..<equalsIndex]).trimmingCharacters(in: .whitespaces)
            let rawValue = String(line[line.index(after: equalsIndex)...])
            let value = unquote(rawValue)
            if key.isEmpty { continue }
            entries.append(Entry(key: key, value: value))
        }
        return entries
    }

    /// Strips matching surrounding single or double quotes and unescapes the single-quote sequence
    /// `'\''` produced by our renderer. Anything else is returned as-is.
    private static func unquote(_ raw: String) -> String {

        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("'") && trimmed.hasSuffix("'") && trimmed.count >= 2 {
            let inner = String(trimmed.dropFirst().dropLast())
            return inner.replacingOccurrences(of: #"'\''"#, with: "'")
        }
        if trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"") && trimmed.count >= 2 {
            return String(trimmed.dropFirst().dropLast())
        }
        return trimmed
    }

}
