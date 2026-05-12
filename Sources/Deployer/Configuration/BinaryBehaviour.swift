import Foundation

/// Retention policy for deployment binaries stored under the target's deploy directory.
enum BinaryBehaviour: Codable, Equatable, Sendable {
    
    /// Retain a fixed number of the most recent binaries.
    case newest(count: Int)
    
    /// Retain binaries until their total size exceeds the specified limit in megabytes.
    case automatic(mb: Int)
    
    /// Retain all binaries indefinitely.
    case all
    
    /// Do not retain any binaries.
    case off
    
}

extension BinaryBehaviour {

    /// The default retention policy for new targets.
    static let setupDefault: BinaryBehaviour = .newest(count: 5)

    /// A string representation of the policy used for setup and CLI interaction.
    var setupValue: String {
        switch self {
        case .newest(let count): "newest:\(count)"
        case .automatic(let mb): "automatic:\(mb)"
        case .all: "all"
        case .off: "off"
        }
    }

    /// Parses a raw string value into a binary retention behaviour.
    static func parse(_ rawValue: String) -> BinaryBehaviour? {
        let value = rawValue.trimmed.lowercased()
        guard !value.isEmpty else { return nil }

        if value == "all" { return .all }
        if value == "off" { return .off }

        let separators = CharacterSet(charactersIn: ":=() ")
        let parts = value
            .components(separatedBy: separators)
            .filter { !$0.isEmpty }

        guard parts.count == 2, let amount = Int(parts[1]), amount > 0 else { return nil }

        return switch parts[0] {
        case "newest": .newest(count: amount)
        case "automatic", "auto": .automatic(mb: amount)
        default: nil
        }
    }

    /// Validates the behaviour's parameters, throwing an error if they are invalid.
    func validated(field: String) throws -> BinaryBehaviour {
        switch self {
        case .newest(let count):
            guard count > 0 else {
                throw Configuration.Error.invalidField(field, "newest count must be greater than 0")
            }
                
        case .automatic(let mb):
            guard mb > 0 else {
                throw Configuration.Error.invalidField(field, "automatic megabyte limit must be greater than 0")
            }
                
        case .all, .off:
            break
        }

        return self
    }

}
