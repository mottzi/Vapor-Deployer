import Foundation

extension BinaryStore {

    enum Error: DescribedError {

        case binaryNotFound(String)
        case binaryAlreadyExists(String)
        case deploymentIDMissing

        var errorDescription: String? {
            switch self {
                case .binaryNotFound(let path): "New binary not found at '\(path)'."
                case .binaryAlreadyExists(let path): "A saved binary already exists at '\(path)'."
                case .deploymentIDMissing: "Deployment ID is missing."
            }
        }

    }

}
