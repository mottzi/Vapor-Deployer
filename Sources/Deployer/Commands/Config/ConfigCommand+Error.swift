import Foundation

extension ConfigCommand {

    enum Error: DescribedError {

        case usage
        case unknownField(String, [String])
        case setupOnlyField(String)
        case binaryInstallNoBranch
        case invalidBoolean(String, String)
        case invalidDeploymentMode(String, String, [String])
        case invalidBinaryBehaviour(String, String)
        case serverBusy(String)
        case serverUnhealthy(String)
        case writeFailed(String, Swift.Error)

        var errorDescription: String? {
            switch self {
            case .usage:
                "Usage: deployer config [<key> <value>]\nRun 'deployer config' with no arguments to list editable fields."

            case .unknownField(let field, let editable):
                "Unknown configuration field '\(field)'. Editable fields: \(editable.joined(separator: ", "))."

            case .setupOnlyField(let field):
                "Field '\(field)' is set at install time and cannot be changed by 'deployer config'. Re-run 'deployerctl setup' to change it."

            case .binaryInstallNoBranch:
                "Field 'deployerBranch' has no effect on this install — buildFromSource is false. Re-run 'deployerctl setup' to switch to a source install."

            case .invalidBoolean(let field, let value):
                "Invalid value '\(value)' for '\(field)'. Expected 'true' or 'false'."

            case .invalidDeploymentMode(let field, let value, let legal):
                "Invalid value '\(value)' for '\(field)'. Expected one of: \(legal.joined(separator: ", "))."

            case .invalidBinaryBehaviour(let field, let value):
                "Invalid value '\(value)' for '\(field)'. Expected 'all', 'off', 'newest:<count>', or 'automatic:<mb>'."

            case .serverBusy(let phase):
                "Deployer is busy (phase: \(phase)). Wait for the current operation to finish, then retry."

            case .serverUnhealthy(let reason):
                "Could not confirm the deployer is ready to restart: \(reason). Stop the deployer service and retry, or run with no restart."

            case .writeFailed(let path, let error):
                "Failed to write configuration to '\(path)': \(error.localizedDescription)"
            }
        }

    }

}
