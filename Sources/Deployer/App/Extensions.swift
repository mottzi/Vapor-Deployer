import Foundation

extension String {
    
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    func trimmingSuffix(_ suffix: String) -> String {
        guard hasSuffix(suffix) else { return self }
        return String(dropLast(suffix.count))
    }
    
    var displayPath: String {
        let segments = self.pathComponents.map(\.description)
        guard !segments.isEmpty else { return "/" }
        let full = "/" + segments.joined(separator: "/")
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard full.hasPrefix(home) else { return full }
        let tail = full.dropFirst(home.count)
        return "~" + tail
    }
    
    var shellQuoted: String {
        "'\(replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }
    
    private static let ansiRegex = try! NSRegularExpression(pattern: "\u{001B}\\[[0-9;?]*[a-zA-Z]")
    
    var ansiStripped: String {
        let range = NSRange(self.startIndex..., in: self)
        let stripped = String.ansiRegex.stringByReplacingMatches(in: self, range: range, withTemplate: "")
        
        return String(stripped.unicodeScalars.filter { scalar in
            scalar == "\n" || scalar == "\r" || scalar == "\t" || (scalar.value >= 32 && scalar.value != 127)
        })
    }
    
}

extension StringProtocol {
    
    var hexadecimalData: Data? {
        
        guard count % 2 == 0 else { return nil }

        var data = Data(capacity: count / 2)
        var index = startIndex

        while index < endIndex {
            let byteEnd = self.index(index, offsetBy: 2)
            guard let byte = UInt8(self[index ..< byteEnd], radix: 16) else { return nil }
            data.append(byte)
            index = byteEnd
        }
        
        return data
    }
    
}
