import Foundation

extension Worker {
    
    enum Error: DescribedError {
        
        case binaryNotFound(String)
        case deploymentFailed(String)
        case deploymentAndRollbackFailed(String, String)

        var errorDescription: String? {
            switch self {
            case .binaryNotFound(let path):
                "New binary not found at '\(path)'."
                
            case .deploymentFailed(let error):
                "Deployment failed: \(error). Rollback successful."
                
            case .deploymentAndRollbackFailed(let error, let rollback):
                "Deployment failed: \(error). Rollback failed: \(rollback)."
            }
        }

    }
    
}
