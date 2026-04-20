import Foundation

/// Escaping helpers for generating shell, systemd, and supervisor templates without injection or parse-breakage from user input.
enum TemplateEscaping {

    /// Escapes a value for systemd/supervisor environment fields so control characters and quotes survive literal parsing.
    static func environmentValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    /// Produces a single-quoted POSIX shell literal, safely encoding embedded single quotes.
    static func shellLiteral(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }

    /// Joins shell arguments into a human-readable command string while quoting only arguments that require it.
    static func shellCommand(_ arguments: [String]) -> String {
        arguments.map(shellDisplayLiteral).joined(separator: " ")
    }

    /// Returns an unquoted token for shell-safe ASCII arguments and falls back to `shellLiteral` for everything else.
    private static func shellDisplayLiteral(_ value: String) -> String {
        
        guard !value.isEmpty else { return shellLiteral(value) }

        let safeCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_@%+=:,./-")
        if value.unicodeScalars.allSatisfy({ safeCharacters.contains($0) }) { return value }

        return shellLiteral(value)
    }

}
