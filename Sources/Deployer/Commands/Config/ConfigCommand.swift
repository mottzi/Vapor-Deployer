import Vapor
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Reads and writes a narrow allowlist of fields in `deployer.json`.
/// See `docs/adr/0006-config-is-an-allowlist.md`.
struct ConfigCommand: AnyAsyncCommand {

    var help: String { "View or modify fields in deployer.json. Run with no arguments to list editable fields." }

    func run(using context: inout CommandContext) async throws {

        let args = context.input.arguments
        context.input.arguments = []

        switch args.count {
            case 0: try await runList(console: context.console)
            case 2: try await runSet(key: args[0], value: args[1], app: context.application, console: context.console)
            default: throw Error.usage
        }
    }

}

extension ConfigCommand {

    /// Formats and displays the editable configuration fields, dynamically annotating values ignored by the current build settings.
    private func runList(console: any Console) async throws {

        let (config, _, _) = try loadRawConfig()

        printBanner(console: console)

        let labelWidth = Field.allCases.map { $0.rawValue.count }.max() ?? 0
        
        for field in Field.allCases {
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

    /// Resolves, validates, and atomically writes a configuration edit, optionally restarting the active daemon.
    private func runSet(key: String, value: String, app: Application, console: any Console) async throws {

        let field = try Field.resolve(key)

        let (oldConfig, configURL, installDirectory) = try loadRawConfig()

        if field == .deployerBranch && !oldConfig.buildFromSource {
            throw Error.binaryInstallNoBranch
        }

        let newConfig = try field.apply(value, to: oldConfig)

        // Validate via the same function that gates the boot path. If this throws, the proposed JSON
        // would fail to load — refuse before touching the file.
        try newConfig.resolved(relativeTo: installDirectory)

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

extension ConfigCommand {

    /// Decodes the configuration file directly to preserve raw layouts and relative paths on save.
    private func loadRawConfig() throws -> (config: Configuration, configURL: URL, installDirectory: URL) {

        let executableURL = try Configuration.getExecutableURL()
        let installDirectory = executableURL.deletingLastPathComponent()
        let configURL = try Configuration.getConfigURL(forExecutableURL: executableURL)

        let data = try Data(contentsOf: configURL)
        let config = try JSONDecoder().decode(Configuration.self, from: data)
        
        return (config, configURL, installDirectory)
    }

    /// Safely encodes and writes the config atomically to prevent file corruption and style churn.
    private func writeAtomically(_ config: Configuration, to url: URL) throws {
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data: Data
        do { data = try encoder.encode(config) }
        catch { throw Error.writeFailed(url.path, error) }

        do { try data.write(to: url, options: [.atomic]) }
        catch { throw Error.writeFailed(url.path, error) }
    }
    
    /// Aborts the config update if the running daemon reports it is currently executing a deployment.
    /// See `ControlPreflight.query` and `docs/adr/0005-cli-server-state-channel.md`.
    private func preflightControlQuery(
        app: Application,
        config: Configuration,
        installDirectory: URL,
        console: any Console
    ) async throws {
        
        switch await ControlPreflight.query(app: app, port: config.port, installDirectory: installDirectory) {
            case .ready: return
            case .busy(let phase): throw Error.serverBusy(phase)
            case .unhealthy(let reason): throw Error.serverUnhealthy(reason)
            case .unreachable(let reason):
                console.print("Warning: deployer server not reachable for state check (\(reason)). Proceeding with restart.")
        }
    }
    
    /// Resolves the service owner and restarts the deployer daemon via the system service manager.
    private func restartDeployer(config: Configuration, installDirectory: URL, console: any Console) async throws {

        let executableURL = installDirectory.appendingPathComponent("deployer", isDirectory: false)
        let serviceUser = await ConfigDiscovery.resolveServiceUser(executableURL: executableURL) ?? ""
        let manager = try config.serviceBackend.makeManager(serviceUser: serviceUser)
        
        try await manager.restart(product: "deployer")
    }
    
    /// Outputs the cyan command header and ruler separating console output sections.
    private func printBanner(console: any Console) {
        console.newLine()
        console.ruler(color: .cyan)
        console.output("  Vapor Deployer · Config".consoleText(color: .cyan, isBold: true))
        console.ruler(color: .cyan)
        console.newLine()
    }

}
