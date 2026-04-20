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
        return "/" + segments.joined(separator: "/")
    }
    
    var shellQuoted: String {
        "'\(replacingOccurrences(of: "'", with: "'\"'\"'"))'"
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
