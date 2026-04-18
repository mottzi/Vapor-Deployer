import Foundation

extension Shell {
    
    struct Error: DescribedError {
        
        let command: String
        let output: String
        
        var errorDescription: String? {
            let trimmedOutput = output.trimmed
            guard !trimmedOutput.isEmpty else { return "Command '\(command)' failed." }
            return "Command '\(command)' failed.\n\(trimmedOutput)"
        }

    }
    
}
