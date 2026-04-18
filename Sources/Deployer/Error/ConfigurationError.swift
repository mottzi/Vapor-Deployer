import Foundation

extension Configuration  {

    enum Error: DescribedError {

        case executablePathUnavailable
        case configNotFound(String)
        case configUnreadable(String, Swift.Error)
        case invalidJSON(String, Swift.Error)
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
