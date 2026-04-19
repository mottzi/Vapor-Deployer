import Foundation

enum TemplateEscaping {

    static func environmentValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    static func shellLiteral(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }

    static func shellCommand(_ arguments: [String]) -> String {
        arguments.map(shellDisplayLiteral).joined(separator: " ")
    }

    private static func shellDisplayLiteral(_ value: String) -> String {
        guard !value.isEmpty else { return shellLiteral(value) }

        let safeCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_@%+=:,./-")
        if value.unicodeScalars.allSatisfy({ safeCharacters.contains($0) }) {
            return value
        }

        return shellLiteral(value)
    }

}
