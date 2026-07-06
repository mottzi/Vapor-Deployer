import Foundation

extension OperationWorker {
    
    enum Error: DescribedError {
        
        case binaryNotFound(String)
        case binaryAlreadyExists(String)
        case deploymentIDMissing
        case deploymentFailed(String)
        case deploymentAndRollbackFailed(String, String)

        var errorDescription: String? {
            switch self {
                case .binaryNotFound(let path): "New binary not found at '\(path)'."
                case .binaryAlreadyExists(let path): "A saved binary already exists at '\(path)'."
                case .deploymentIDMissing: "Deployment ID is missing."
                case .deploymentFailed(let error): "Deployment failed: \(error). Rollback successful."
                case .deploymentAndRollbackFailed(let error, let rollback): "Deployment failed: \(error). Rollback failed: \(rollback)."
            }
        }

    }
    
}
