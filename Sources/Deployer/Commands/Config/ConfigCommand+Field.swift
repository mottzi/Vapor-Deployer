import Foundation

extension ConfigCommand {

    /// Allowlist of `deployer.json` fields that `deployer config` can modify in place. Every other field
    /// in `Configuration` / `TargetConfiguration` is set at install time and changing it without re-running
    /// setup would desynchronize the JSON from on-disk state (nginx, systemd unit, clone path, …). See
    /// `docs/adr/0006-config-is-an-allowlist.md`.
    enum Field: String, CaseIterable {

        case deployerBranch        = "deployerBranch"
        case targetBranch          = "target.branch"
        case targetBuildMode       = "target.buildMode"
        case targetDeploymentMode  = "target.deploymentMode"
        case targetBinaryBehaviour = "target.binaryBehaviour"
        case targetTesting         = "target.testing"
        case targetHealthCheckPath       = "target.healthCheckPath"
        case targetHealthCheckInterval   = "target.healthCheckIntervalMs"
        case targetHealthCheckMaxRetries = "target.healthCheckMaxRetries"
        case targetHealthCheckTimeout    = "target.healthCheckTimeoutMs"

        /// Known setup-time field names. Used to give a friendly redirect-to-setup error when the user names
        /// one of these — distinct from unknown-field errors. List is exhaustive for `Configuration` and
        /// `TargetConfiguration` minus the editable set.
        static let setupOnlyFields: [String] = [
            "port",
            "dbFile",
            "deployerDirectory",
            "socketPath",
            "panelRoute",
            "serviceHome",
            "swiftPath",
            "serviceBackend",
            "buildFromSource",
            "webhookSecret",
            "target.name",
            "target.repositoryURL",
            "target.directory",
            "target.pusheventPath",
            "target.appPort",
        ]

        /// Looks up a key string against the editable set, returning the matching field or throwing a
        /// targeted error (setup-only vs. unknown).
        static func resolve(_ key: String) throws -> Field {
            if let field = Field(rawValue: key) { return field }
            if setupOnlyFields.contains(key) { throw ConfigCommand.Error.setupOnlyField(key) }
            throw ConfigCommand.Error.unknownField(key, allCases.map { $0.rawValue })
        }

        /// Current value of the field as it appears in the on-disk JSON, formatted for human display.
        func currentValue(in config: Configuration) -> String {
            switch self {
                case .deployerBranch:        config.deployerBranch
                case .targetBranch:          config.target.branch
                case .targetBuildMode:       config.target.buildMode
                case .targetDeploymentMode:  config.target.deploymentMode.rawValue
                case .targetBinaryBehaviour: config.target.binaryBehaviour.setupValue
                case .targetTesting:         String(config.target.testing)
                case .targetHealthCheckPath:       config.target.healthCheckPath ?? "nil"
                case .targetHealthCheckInterval:   config.target.healthCheckIntervalMs.map(String.init) ?? "nil"
                case .targetHealthCheckMaxRetries: config.target.healthCheckMaxRetries.map(String.init) ?? "nil"
                case .targetHealthCheckTimeout:    config.target.healthCheckTimeoutMs.map(String.init) ?? "nil"
            }
        }

        /// Human-facing value for list output. Keeps `currentValue(in:)` raw so no-op detection and write
        /// reporting compare the actual serialized configuration value.
        func displayValue(in config: Configuration) -> String {
            if self == .deployerBranch && !config.buildFromSource {
                return "\(config.deployerBranch) (ignored; buildFromSource is false)"
            }

            return currentValue(in: config)
        }

        /// Parses the raw input string for this field's type and returns a new `Configuration` with the
        /// change applied. Throws `ConfigCommand.Error` on parse failure. The returned value has not yet
        /// been run through `Configuration.resolved()` — the caller does that round-trip for invariant
        /// validation before writing.
        func apply(_ input: String, to config: Configuration) throws -> Configuration {

            let trimmedInput = input.trimmed
            var config = config

            switch self {
                case .targetDeploymentMode:
                    let lowered = trimmedInput.lowercased()
                    guard let mode = DeploymentMode(rawValue: lowered) else {
                        let legal = ["automatic", "manual"]
                        throw ConfigCommand.Error.invalidDeploymentMode(rawValue, input, legal)
                    }
                    config.target.deploymentMode = mode

                case .targetBinaryBehaviour:
                    guard let behaviour = BinaryBehaviour.parse(input) else {
                        throw ConfigCommand.Error.invalidBinaryBehaviour(rawValue, input)
                    }
                    config.target.binaryBehaviour = behaviour

                case .targetTesting:
                    let lowered = trimmedInput.lowercased()
                    guard lowered == "true" || lowered == "false" else {
                        throw ConfigCommand.Error.invalidBoolean(rawValue, input)
                    }
                    config.target.testing = lowered == "true"
                
                case .deployerBranch: config.deployerBranch = trimmedInput
                case .targetBranch: config.target.branch = trimmedInput
                case .targetBuildMode: config.target.buildMode = trimmedInput
                case .targetHealthCheckPath: config.target.healthCheckPath = trimmedInput == "nil" ? nil : trimmedInput
                case .targetHealthCheckInterval: config.target.healthCheckIntervalMs = trimmedInput == "nil" ? nil : Int(trimmedInput)
                case .targetHealthCheckMaxRetries: config.target.healthCheckMaxRetries = trimmedInput == "nil" ? nil : Int(trimmedInput)
                case .targetHealthCheckTimeout: config.target.healthCheckTimeoutMs = trimmedInput == "nil" ? nil : Int(trimmedInput)
            }

            return config
        }

    }

}
