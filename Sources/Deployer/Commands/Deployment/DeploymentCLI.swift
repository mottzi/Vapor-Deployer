import Vapor
import Fluent

/// Shared helpers for top-level deployment CLI commands.
enum DeploymentCLI {

    static let defaultListLimit = 20

    /// Loads the headless runtime and returns the config plus shared engine.
    static func runtime(from context: CommandContext) async throws -> (Configuration, OperationEngine) {
        
        let config = try await context.application.deployer.useHeadlessRuntime()
        let engine = OperationEngine(app: context.application, config: config, origin: .cli)
        
        return (config, engine)
    }

    /// Runs a mutating CLI operation under the global operation lock.
    static func runLocked<T>(context: CommandContext, operation: () async throws -> T) async throws -> T {
        
        let lock = try OperationLock.acquire()
        defer { lock.release() }
        
        return try await operation()
    }

    /// Parses positional arguments and simple boolean flags.
    static func parse(_ arguments: [String]) throws -> ParsedArguments {
        
        var positionals: [String] = []
        var flags: Set<String> = []

        for argument in arguments {
            if argument.hasPrefix("-") {
                flags.insert(argument)
            } else {
                positionals.append(argument)
            }
        }

        return ParsedArguments(positionals: positionals, flags: flags)
    }

    /// Ensures only the expected flags were supplied.
    static func validateFlags(_ parsed: ParsedArguments, allowed: Set<String>) throws {
        let unknown = parsed.flags.subtracting(allowed)
        guard unknown.isEmpty else { throw Error.unknownFlags(Array(unknown).sorted()) }
    }

    /// Renders the deployment list as the compact operator table.
    static func printDeploymentList(
        config: Configuration,
        app: Application,
        console: any Console,
        limit: Int? = nil
    ) async throws {

        let deployments = try await Deployment.query(on: app.db)
            .filter(\.$product, .equal, config.target.name)
            .sort(\.$createdAt, .descending)
            .limit(limit ?? defaultListLimit)
            .all()

        guard !deployments.isEmpty else {
            console.output("No deployments found.")
            return
        }

        let width = Host.Terminal.current()
        let commitWidth = max(width - 74, 12)

        console.output("L  STATUS     SHA      TESTS  BINARY    STARTED           DUR    COMMIT".consoleText(isBold: true))
        for deployment in deployments {
            let live = deployment.isLive ? "*" : " "
            let status = deployment.displayStatus.rawValue.padding(toLength: 10, withPad: " ", startingAt: 0)
            let sha = deployment.shortSHA.padding(toLength: 8, withPad: " ", startingAt: 0)
            let tests = testLabel(for: deployment).padding(toLength: 6, withPad: " ", startingAt: 0)
            let binary = binaryLabel(for: deployment).padding(toLength: 9, withPad: " ", startingAt: 0)
            let started = startedLabel(for: deployment).padding(toLength: 17, withPad: " ", startingAt: 0)
            let duration = (deployment.durationString ?? "-").padding(toLength: 6, withPad: " ", startingAt: 0)
            let message = truncate(deployment.commitMessage, to: commitWidth)
            console.output("\(live)  \(status) \(sha) \(tests) \(binary) \(started) \(duration) \(message)")
        }
    }

    /// Reports the shared successful no-op used when a promotion target is already active.
    static func printAlreadyLive(_ deployment: Deployment, console: any Console) {
        console.output("\(deployment.shortSHA) is already live.")
    }

    /// Parses testing flags into an explicit test policy, requiring confirmation if tests are being skipped.
    static func testPolicy(parsed: ParsedArguments, target: TargetConfiguration) throws -> OperationEngine.TestPolicy {
        
        if parsed.flags.contains("--testing") || parsed.flags.contains("-t") {
            return .forceEnabled
        }

        if parsed.flags.contains("--skip-tests") {
            guard parsed.flags.contains("--yes") else { throw Operation.Error.skipTestsRequiresConfirmation }
            return .forceDisabled
        }

        return .configured
    }

    /// Returns an event sink that streams operation logs to the terminal unless the --no-logs flag is present.
    static func consoleSink(parsed: ParsedArguments, console: any Console) -> OperationOutputConsoleSink? {
        parsed.flags.contains("--no-logs") ? nil : OperationOutputConsoleSink(console: console)
    }
    
    /// Prompts the operator for interactive confirmation unless the non-interactive --yes flag was provided.
    static func confirmIfNeeded(_ message: String, parsed: ParsedArguments, console: any Console) throws {
        guard !parsed.flags.contains("--yes") else { return }
        guard console.confirm(message, defaultYes: false) else { throw Error.aborted }
    }

}

extension DeploymentCLI {

    struct ParsedArguments {
        let positionals: [String]
        let flags: Set<String>
    }

    enum Error: DescribedError {
        
        case usage(String)
        case unknownFlags([String])
        case aborted

        var errorDescription: String? {
            switch self {
                case .usage(let usage): usage
                case .unknownFlags(let flags): "Unknown flag(s): \(flags.joined(separator: ", "))"
                case .aborted: "Aborted."
            }
        }
        
    }

}

extension DeploymentCLI {

    private static func testLabel(for deployment: Deployment) -> String {
        if deployment.testsPassed { return "ok" }
        if deployment.testsFailed { return "fail" }
        return "-"
    }

    private static func binaryLabel(for deployment: Deployment) -> String {
        guard let mb = deployment.binarySizeMB else { return "-" }
        return "\(mb) MB"
    }

    private static func startedLabel(for deployment: Deployment) -> String {
        guard let date = deployment.startedAt else { return "-" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    private static func truncate(_ text: String, to maxLength: Int) -> String {
        guard text.count > maxLength else { return text }
        guard maxLength > 1 else { return String(text.prefix(maxLength)) }
        guard maxLength > 3 else { return String(text.prefix(maxLength)) }
        return String(text.prefix(maxLength - 3)) + "..."
    }

}
