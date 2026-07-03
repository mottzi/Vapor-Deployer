import Foundation

enum LogSanitizer {

    private static let ansiRegex = try! NSRegularExpression(pattern: "\u{001B}\\[[0-9;?]*[a-zA-Z]")

    static func sanitize(_ text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        let stripped = ansiRegex.stringByReplacingMatches(in: text, range: range, withTemplate: "")

        return String(stripped.unicodeScalars.filter { scalar in
            scalar == "\n" || scalar == "\r" || scalar == "\t" || (scalar.value >= 32 && scalar.value != 127)
        })
    }

}
