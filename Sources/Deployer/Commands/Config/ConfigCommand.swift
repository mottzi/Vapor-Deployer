import Vapor
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Reads and writes a narrow allowlist of fields in `deployer.json`. See `docs/adr/0006-config-is-an-allowlist.md`
/// for the editable set and the rationale. Conforms to `AnyAsyncCommand` directly (rather than `AsyncCommand`)
/// because the command takes optional positional arguments (`config` vs. `config <key> <value>`) and the
/// `AsyncCommand` default machinery rejects leftover positional input.
struct ConfigCommand: AnyAsyncCommand {

    var help: String { "View or modify fields in deployer.json. Run with no arguments to list editable fields." }

    func run(using context: inout CommandContext) async throws {

        let args = context.input.arguments
        context.input.arguments = []

        switch args.count {
        case 0:
            try await runList(console: context.console)
        case 2:
            try await runSet(key: args[0], value: args[1], app: context.application, console: context.console)
        default:
            throw Error.usage
        }
    }

}

private extension ConfigCommand {

    /// Prints the 6 editable fields and their current on-disk values.
    func runList(console: any Console) async throws {

        let (config, _, _) = try loadRawConfig()

        printBanner(console: console)

        let labelWidth = ConfigField.allCases.map { $0.rawValue.count }.max() ?? 0
        for field in ConfigField.allCases {
            let label = field.rawValue.padding(toLength: labelWidth, withPad: " ", startingAt: 0)
            console.output(
                "  \(label)".consoleText(color: .cyan)
                + " = ".consoleText()
                + field.displayValue(in: config).consoleText(isBold: true)
            )
        }
        console.newLine()
        console.output("  To change a setting, use 'deployerctl config <field> <value>'.".consoleText())
        console.newLine()
    }

    /// Applies a single field edit. Order: resolve key → load raw JSON → parse and apply input → validate
    /// via `Configuration.resolved()` round-trip → preflight control query if user wants restart → write
    /// atomically → restart if requested.
    func runSet(key: String, value: String, app: Application, console: any Console) async throws {

        let field = try ConfigField.resolve(key)

        let (oldConfig, configURL, installDirectory) = try loadRawConfig()

        if field == .deployerBranch && !oldConfig.buildFromSource {
            throw Error.binaryInstallNoBranch
        }

        let newConfig = try field.apply(value, to: oldConfig)

        // Validate via the same function that gates the boot path. If this throws, the proposed JSON
        // would fail to load — refuse before touching the file.
        _ = try newConfig.resolved(relativeTo: installDirectory)

        // No-op detection: compare the rendered value after normalization, not the raw input string.
        // (`automatic:5` and `auto:5` parse to the same BinaryBehaviour; `True`/`true` are the same Bool.)
        if field.currentValue(in: oldConfig) == field.currentValue(in: newConfig) {
            console.output("  \(field.rawValue) is already \(field.currentValue(in: oldConfig)); no change.".consoleText(color: .yellow))
            return
        }

        console.newLine()
        console.output("  \(field.rawValue)".consoleText(color: .cyan)
            + ": ".consoleText()
            + field.currentValue(in: oldConfig).consoleText()
            + " → ".consoleText()
            + field.currentValue(in: newConfig).consoleText(isBold: true))
        console.newLine()
        console.output("  This change will only take effect after the deployer service restarts.".consoleText())

        let wantsRestart = console.confirm("Restart the deployer now?", defaultYes: true)

        if wantsRestart {
            // Preflight before the write: if the server is busy, refuse the whole operation rather
            // than leave a JSON-disagrees-with-runtime window.
            // See `docs/adr/0005-cli-server-state-channel.md` and `docs/adr/0006-config-is-an-allowlist.md`.
            try await preflightControlQuery(
                app: app,
                config: oldConfig,
                installDirectory: installDirectory,
                console: console
            )
        }

        try writeAtomically(newConfig, to: configURL)

        if wantsRestart {
            try await restartDeployer(config: oldConfig, installDirectory: installDirectory, console: console)
            console.output("  Restart triggered. New value is live.".consoleText(color: .green))
        } else {
            console.output("  Saved to deployer.json. The new value will apply on the next deployer restart.".consoleText(color: .yellow))
        }
    }

}

private extension ConfigCommand {

    /// Decodes `deployer.json` *without* the `resolved()` normalization pass. This preserves the on-disk
    /// shape (relative paths stay relative, etc.) so that round-tripping through encode/write doesn't
    /// rewrite fields the user didn't touch. Returns the raw config, the config-file URL, and the
    /// install directory.
    func loadRawConfig() throws -> (Configuration, URL, URL) {

        let executableURL = try Configuration.getExecutableURL()
        let installDirectory = executableURL.deletingLastPathComponent()
        let configURL = try Configuration.getConfigURL(forExecutableURL: executableURL)

        let data = try Data(contentsOf: configURL)
        let config = try JSONDecoder().decode(Configuration.self, from: data)
        return (config, configURL, installDirectory)
    }

    /// Encodes the new config and writes it via `Data.write(.atomic)`, which writes to a sibling temp
    /// file and atomically renames over the original. Encoder settings (`prettyPrinted`, `sortedKeys`)
    /// match `DeployerTemplate` so the file shape doesn't churn between Setup-written and config-written
    /// states.
    func writeAtomically(_ config: Configuration, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data: Data
        do { data = try encoder.encode(config) }
        catch { throw Error.writeFailed(url.path, error) }

        do { try data.write(to: url, options: [.atomic]) }
        catch { throw Error.writeFailed(url.path, error) }
    }

}

private extension ConfigCommand {

    // See `ControlPreflight.query` and `docs/adr/0005-cli-server-state-channel.md`.
    func preflightControlQuery(app: Application, config: Configuration, installDirectory: URL, console: any Console) async throws {
        switch await ControlPreflight.query(app: app, port: config.port, installDirectory: installDirectory) {
            case .ready: return
            case .busy(let phase): throw Error.serverBusy(phase)
            case .unhealthy(let reason): throw Error.serverUnhealthy(reason)
            case .unreachable(let reason):
                console.print("Warning: deployer server not reachable for state check (\(reason)). Proceeding with restart.")
        }
    }

}

private extension ConfigCommand {

    /// Restarts the deployer service via the configured `ServiceManagerKind`. Same primitive used by
    /// `SetupCommand` rollback and by `UpdateCommand` post-swap. Service user is resolved from
    /// `/etc/deployer/deployerctl.conf` first, then falls back to the executable file owner.
    func restartDeployer(config: Configuration, installDirectory: URL, console: any Console) async throws {

        let executableURL = installDirectory.appendingPathComponent("deployer", isDirectory: false)
        let serviceUser = await ConfigDiscovery.resolveServiceUser(executableURL: executableURL) ?? ""
        let manager = try config.serviceManager.makeManager(serviceUser: serviceUser)
        try await manager.restart(product: "deployer")
    }

}

private extension ConfigCommand {

    func printBanner(console: any Console) {
        console.newLine()
        console.ruler(color: .cyan)
        console.output("  Vapor Deployer · Config".consoleText(color: .cyan, isBold: true))
        console.ruler(color: .cyan)
        console.newLine()
    }

}
