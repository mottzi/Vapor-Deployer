import Foundation

/// Allowlist of `deployer.json` fields that `deployer config` can modify in place. Every other field
/// in `Configuration` / `TargetConfiguration` is set at install time and changing it without re-running
/// setup would desynchronize the JSON from on-disk state (nginx, systemd unit, clone path, …). See
/// `docs/adr/0006-config-is-an-allowlist.md`.
enum ConfigField: String, CaseIterable, Sendable {

    case deployerBranch        = "deployerBranch"
    case targetBranch          = "target.branch"
    case targetBuildMode       = "target.buildMode"
    case targetDeploymentMode  = "target.deploymentMode"
    case targetBinaryBehaviour = "target.binaryBehaviour"
    case targetTesting         = "target.testing"

    /// Known setup-time field names. Used to give a friendly redirect-to-setup error when the user names
    /// one of these — distinct from unknown-field errors. List is exhaustive for `Configuration` and
    /// `TargetConfiguration` minus the editable set.
    static let setupOnlyFields: [String] = [
        "port",
        "dbFile",
        "deployerDirectory",
        "socketPath",
        "panelRoute",
        "serviceManager",
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
    static func resolve(_ key: String) throws -> ConfigField {
        if let field = ConfigField(rawValue: key) { return field }
        if setupOnlyFields.contains(key) { throw ConfigCommand.Error.setupOnlyField(key) }
        throw ConfigCommand.Error.unknownField(key, allCases.map { $0.rawValue })
    }

    /// Current value of the field as it appears in the on-disk JSON, formatted for human display.
    func currentValue(in config: Configuration) -> String {
        switch self {
        case .deployerBranch:        return config.deployerBranch
        case .targetBranch:          return config.target.branch
        case .targetBuildMode:       return config.target.buildMode
        case .targetDeploymentMode:  return config.target.deploymentMode.rawValue
        case .targetBinaryBehaviour: return config.target.binaryBehaviour.setupValue
        case .targetTesting:         return String(config.target.testing)
        }
    }

    /// Parses the raw input string for this field's type and returns a new `Configuration` with the
    /// change applied. Throws `ConfigCommand.Error` on parse failure. The returned value has not yet
    /// been run through `Configuration.resolved()` — the caller does that round-trip for invariant
    /// validation before writing.
    func apply(_ input: String, to config: Configuration) throws -> Configuration {

        switch self {
        case .deployerBranch:
            return config.replacing(deployerBranch: input.trimmed)

        case .targetBranch:
            return config.replacingTarget(config.target.replacing(branch: input.trimmed))

        case .targetBuildMode:
            return config.replacingTarget(config.target.replacing(buildMode: input.trimmed))

        case .targetDeploymentMode:
            let lowered = input.trimmed.lowercased()
            guard let mode = DeploymentMode(rawValue: lowered) else {
                let legal = ["automatic", "manual"]
                throw ConfigCommand.Error.invalidDeploymentMode(rawValue, input, legal)
            }
            return config.replacingTarget(config.target.replacing(deploymentMode: mode))

        case .targetBinaryBehaviour:
            guard let behaviour = BinaryBehaviour.parse(input) else {
                throw ConfigCommand.Error.invalidBinaryBehaviour(rawValue, input)
            }
            return config.replacingTarget(config.target.replacing(binaryBehaviour: behaviour))

        case .targetTesting:
            let lowered = input.trimmed.lowercased()
            guard lowered == "true" || lowered == "false" else {
                throw ConfigCommand.Error.invalidBoolean(rawValue, input)
            }
            return config.replacingTarget(config.target.replacing(testing: lowered == "true"))
        }
    }

}

private extension Configuration {

    func replacing(deployerBranch: String) -> Configuration {
        Configuration(
            port: self.port,
            dbFile: self.dbFile,
            deployerDirectory: self.deployerDirectory,
            socketPath: self.socketPath,
            panelRoute: self.panelRoute,
            target: self.target,
            serviceManager: self.serviceManager,
            buildFromSource: self.buildFromSource,
            deployerBranch: deployerBranch,
            webhookSecret: self.webhookSecret
        )
    }

    func replacingTarget(_ target: TargetConfiguration) -> Configuration {
        Configuration(
            port: self.port,
            dbFile: self.dbFile,
            deployerDirectory: self.deployerDirectory,
            socketPath: self.socketPath,
            panelRoute: self.panelRoute,
            target: target,
            serviceManager: self.serviceManager,
            buildFromSource: self.buildFromSource,
            deployerBranch: self.deployerBranch,
            webhookSecret: self.webhookSecret
        )
    }

}

private extension TargetConfiguration {

    func replacing(branch: String) -> TargetConfiguration {
        TargetConfiguration(
            name: self.name,
            repositoryURL: self.repositoryURL,
            directory: self.directory,
            buildMode: self.buildMode,
            pusheventPath: self.pusheventPath,
            deploymentMode: self.deploymentMode,
            binaryBehaviour: self.binaryBehaviour,
            appPort: self.appPort,
            branch: branch,
            testing: self.testing
        )
    }

    func replacing(buildMode: String) -> TargetConfiguration {
        TargetConfiguration(
            name: self.name,
            repositoryURL: self.repositoryURL,
            directory: self.directory,
            buildMode: buildMode,
            pusheventPath: self.pusheventPath,
            deploymentMode: self.deploymentMode,
            binaryBehaviour: self.binaryBehaviour,
            appPort: self.appPort,
            branch: self.branch,
            testing: self.testing
        )
    }

    func replacing(deploymentMode: DeploymentMode) -> TargetConfiguration {
        TargetConfiguration(
            name: self.name,
            repositoryURL: self.repositoryURL,
            directory: self.directory,
            buildMode: self.buildMode,
            pusheventPath: self.pusheventPath,
            deploymentMode: deploymentMode,
            binaryBehaviour: self.binaryBehaviour,
            appPort: self.appPort,
            branch: self.branch,
            testing: self.testing
        )
    }

    func replacing(binaryBehaviour: BinaryBehaviour) -> TargetConfiguration {
        TargetConfiguration(
            name: self.name,
            repositoryURL: self.repositoryURL,
            directory: self.directory,
            buildMode: self.buildMode,
            pusheventPath: self.pusheventPath,
            deploymentMode: self.deploymentMode,
            binaryBehaviour: binaryBehaviour,
            appPort: self.appPort,
            branch: self.branch,
            testing: self.testing
        )
    }

    func replacing(testing: Bool) -> TargetConfiguration {
        TargetConfiguration(
            name: self.name,
            repositoryURL: self.repositoryURL,
            directory: self.directory,
            buildMode: self.buildMode,
            pusheventPath: self.pusheventPath,
            deploymentMode: self.deploymentMode,
            binaryBehaviour: self.binaryBehaviour,
            appPort: self.appPort,
            branch: self.branch,
            testing: testing
        )
    }

}
