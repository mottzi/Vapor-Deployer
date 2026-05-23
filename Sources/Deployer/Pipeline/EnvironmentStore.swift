import Foundation
import Logging

/// Reads and writes the target app's `.env` file. Source of truth (ADR 0008).
struct EnvironmentStore {

    /// Absolute path to the target's `.env`, e.g. `/home/vapor/apps/<appName>/.env`.
    let envFilePath: String

    struct Entry: Equatable, Sendable {
        let key: String
        let value: String
    }

    /// Validation problem on a specific row, or on the form as a whole when `rowIndex` is nil.
    struct ValidationIssue: Equatable, Sendable {
        let rowIndex: Int?
        let message: String
    }

    enum LoadError: Error {
        /// The file exists but could not be read; wraps the underlying I/O error.
        case readFailed(String, underlying: Error)
    }

    enum SaveError: Error {
        /// One or more entries failed validation; contains every issue found.
        case validation([ValidationIssue])
        /// The file was valid but the write failed; wraps the underlying I/O error.
        case writeFailed(String, underlying: Error)
    }

}

extension EnvironmentStore {

    /// Returns the current entries. Missing file → `[]`; malformed lines → skipped.
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

        return EnvironmentStore.parse(raw)
    }

    /// Validates, renders, and writes the file atomically with mode 0600.
    /// Permissions are tightened after every write — first creation inherits the process umask
    /// (often 0022, world-readable), so the chmod is re-applied for idempotence.
    func save(_ entries: [Entry], logger: Logger? = nil) throws {

        let issues = EnvironmentStore.validate(entries)
        guard issues.isEmpty else { throw SaveError.validation(issues) }

        let data = Data(EnvironmentStore.render(entries).utf8)
        guard data.count <= EnvironmentStore.maxFileBytes else {
            throw SaveError.validation([ValidationIssue(
                rowIndex: nil,
                message: "File would be \(data.count) bytes; maximum is \(EnvironmentStore.maxFileBytes)."
            )])
        }

        let url = URL(fileURLWithPath: envFilePath)
        do {
            try data.write(to: url, options: [.atomic])
        } catch {
            throw SaveError.writeFailed(envFilePath, underlying: error)
        }

        do {
            try FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: Int16(0o600))],
                ofItemAtPath: envFilePath
            )
        } catch {
            logger?.warning("Failed to set 0600 permissions on \(envFilePath): \(error)")
        }
    }

}

extension EnvironmentStore {
    
    /// Sanity bound on rendered file size; not a security limit.
    static let maxFileBytes = 64 * 1024
    
    /// POSIX permits longer keys, but anything legitimate is well under this.
    static let maxKeyLength = 128
    
    /// Single-line tokens (URLs, JWTs, base64 secrets) fit comfortably under 4 KB.
    static let maxValueLength = 4096
    
    /// Set by the service manager; overrides here would be ignored or confusing.
    static let reservedKeys: Set<String> = ["PATH", "HOME", "USER"]
    
    /// POSIX env-var name.
    private static let keyPattern = #"^[A-Z_][A-Z0-9_]*$"#
    
}

extension EnvironmentStore {

    /// Returns one issue per problem found. Empty result means safe to render.
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
                issues.append(.init(rowIndex: index, message: "Key must start with a letter or underscore and contain only uppercase letters, digits, and underscores."))
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
            if value.contains(#"\n"#) {
                issues.append(.init(rowIndex: index, message: #"Value cannot contain the literal sequence \n."#))
            }
        }

        return issues
    }

    /// Renders the canonical `.env`. One `load → save` cycle normalizes any pre-existing formatting drift.
    static func render(_ entries: [Entry]) -> String {

        var lines: [String] = ["# Managed by Vapor Deployer. Edits made by hand may be overwritten."]
        
        for entry in entries {
            lines.append(#"\#(entry.key)="\#(entry.value)""#)
        }
        
        return lines.joined(separator: "\n") + "\n"
    }

    /// Lenient line parser: `KEY=VALUE` with optional single/double quotes, skipping blanks and `#` comments.
    /// Malformed lines are dropped — `render` re-canonicalizes on next save.
    static func parse(_ raw: String) -> [Entry] {

        var entries: [Entry] = []
        
        for rawLine in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let equalsIndex = line.firstIndex(of: "=") else { continue }
            
            let key = String(line[line.startIndex..<equalsIndex]).trimmingCharacters(in: .whitespaces)
            if key.isEmpty { continue }
            
            let rawValue = String(line[line.index(after: equalsIndex)...])
            let value = unquote(rawValue)
            
            entries.append(Entry(key: key, value: value))
        }
        
        return entries
    }

    /// Strips matching outer quotes; unwraps `'\''` from values written by the legacy renderer.
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
