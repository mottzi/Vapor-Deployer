import Foundation

/// Errors shared across setup and remove commands for common host-level operations.
enum SystemError: DescribedError {

    case notRoot
    case unsupportedOperatingSystem(String)
    case serviceTimeout(String)
    case missingValue(String)
    case invalidValue(String, String)

    var errorDescription: String? {
        switch self {
        case .notRoot:
            "This command requires privileges. Run as root or with sudo."

        case .unsupportedOperatingSystem(let id):
            "This command currently supports Ubuntu only. Detected: \(id)."

        case .serviceTimeout(let service):
            "Service '\(service)' did not reach a running state before the timeout."

        case .missingValue(let value):
            "Required value '\(value)' has not been collected yet."

        case .invalidValue(let field, let reason):
            "Invalid value '\(field)': \(reason)"
        }
    }

}
