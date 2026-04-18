import Foundation

extension Configuration  {
    
    enum LoadError: LocalizedError {
        
        /// Thrown when the process executable path cannot be determined.
        case executablePathUnavailable
        
        /// Thrown when the sibling JSON config file does not exist.
        case configNotFound(String)
        
        /// Thrown when the sibling JSON config file exists but cannot be read.
        case configUnreadable(String, Error)
        
        /// Thrown when the JSON file cannot be decoded into the expected schema.
        case invalidJSON(String, Error)
        
        /// Thrown when a decoded field fails runtime validation.
        case invalidField(String, String)
        
        
        var errorDescription: String? {
            switch self {
            case .executablePathUnavailable:
                "Unable to determine the executable path for Deployer configuration loading."
                
            case .configNotFound(let path):
                "Deployer configuration file not found at '\(path)'."
                
            case .configUnreadable(let path, let error):
                "Failed to read Deployer configuration at '\(path)': \(error.localizedDescription)"
                
            case .invalidJSON(let path, let error):
                "Invalid Deployer configuration JSON at '\(path)': \(error.localizedDescription)"
                
            case .invalidField(let field, let reason):
                "Invalid Deployer configuration field '\(field)': \(reason)"
            }
        }

    }
    
}
