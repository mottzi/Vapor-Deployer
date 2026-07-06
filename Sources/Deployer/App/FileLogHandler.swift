import Logging
import Foundation

/// Appends log records to a file on disk, matching the timestamp format used by the daemon's console logger.
///
/// Used exclusively in headless CLI mode so that framework and database logs are written to the shared
/// `deployer.log` file (visible in the panel log viewer) instead of leaking into the terminal's
/// clean operation transcript.
struct FileLogHandler: LogHandler {
    
    var metadata: Logger.Metadata = [:]
    var logLevel: Logger.Level = .info
    
    private let fileHandle: FileHandle

    init(fileHandle: FileHandle) {
        self.fileHandle = fileHandle
    }

    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    func log(event: LogEvent) {
        let timestamp = Self.formatter.string(from: Date())
        let levelName = event.level.rawValue.uppercased()
        
        var outputLine = "\(timestamp) [ \(levelName) ] \(event.message)"
        
        let merged = mergedMetadata(explicit: event.metadata)
        if !merged.isEmpty {
            let rendered = merged.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
            outputLine += " [\(rendered)]"
        }
        
        outputLine += "\n"
        
        if let data = outputLine.data(using: .utf8) {
            fileHandle.write(data)
        }
    }
    
    private func mergedMetadata(explicit: Logger.Metadata?) -> Logger.Metadata {
        
        guard let explicit else { return metadata }
        guard !metadata.isEmpty else { return explicit }
        
        return metadata.merging(explicit) { _, new in new }
    }
    
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
    
}
