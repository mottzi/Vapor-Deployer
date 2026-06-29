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
        "serviceHome",
        "swiftPath",
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
        return switch self {
        case .deployerBranch:        config.deployerBranch
        case .targetBranch:          config.target.branch
        case .targetBuildMode:       config.target.buildMode
        case .targetDeploymentMode:  config.target.deploymentMode.rawValue
        case .targetBinaryBehaviour: config.target.binaryBehaviour.setupValue
        case .targetTesting:         String(config.target.testing)
        }
    }

    /// Parses the raw input string for this field's type and returns a new `Configuration` with the
    /// change applied. Throws `ConfigCommand.Error` on parse failure. The returned value has not yet
    /// been run through `Configuration.resolved()` — the caller does that round-trip for invariant
    /// validation before writing.
    func apply(_ input: String, to config: Configuration) throws -> Configuration {

        var copy = config

        switch self {
        case .deployerBranch:
            copy.deployerBranch = input.trimmed

        case .targetBranch:
            copy.target.branch = input.trimmed

        case .targetBuildMode:
            copy.target.buildMode = input.trimmed

        case .targetDeploymentMode:
            let lowered = input.trimmed.lowercased()
            guard let mode = DeploymentMode(rawValue: lowered) else {
                let legal = ["automatic", "manual"]
                throw ConfigCommand.Error.invalidDeploymentMode(rawValue, input, legal)
            }
            copy.target.deploymentMode = mode

        case .targetBinaryBehaviour:
            guard let behaviour = BinaryBehaviour.parse(input) else {
                throw ConfigCommand.Error.invalidBinaryBehaviour(rawValue, input)
            }
            copy.target.binaryBehaviour = behaviour

        case .targetTesting:
            let lowered = input.trimmed.lowercased()
            guard lowered == "true" || lowered == "false" else {
                throw ConfigCommand.Error.invalidBoolean(rawValue, input)
            }
            copy.target.testing = lowered == "true"
        }

        return copy
    }

}
