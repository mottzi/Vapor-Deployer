import Foundation

extension Shell {
    
    struct Error: LocalizedError, CustomStringConvertible, CustomDebugStringConvertible {
        
        let command: String
        let output: String
        
        var errorDescription: String? {
            let trimmedOutput = output.trimmed
            guard !trimmedOutput.isEmpty else { return "Command '\(command)' failed." }
            return "Command '\(command)' failed.\n\(trimmedOutput)"
        }

        var description: String {
            errorDescription ?? "Shell command failed."
        }

        var debugDescription: String {
            description
        }
        
    }
    
}
