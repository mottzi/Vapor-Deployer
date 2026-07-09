import Foundation
import Vapor

extension Deployer {
    
    /// Prevents help and one-shot commands from triggering stateful server boot; only implicit and explicit `serve` executions opt in.
    static func shouldConfigureServer(for environment: Environment) -> Bool {
        
        let commandArguments = environment.arguments.dropFirst()
        guard !commandArguments.contains(where: { $0 == "--help" || $0 == "-h" }) else { return false }
        
        let command = commandArguments.first { !$0.hasPrefix("-") }
        return command == nil || command == "serve"
    }
    
}

extension Deployer {

    /// Assembles the long-lived runtime before Vapor serves requests, repairing persisted operations before exposing panel and control surfaces.
    func useServer() async throws {

        let config = try Configuration.load()
        app.logger.info("Initializing Deployer server runtime with service manager: \(config.serviceBackend)")

        try useVariables()
        app.deployer.serviceManager = try config.serviceBackend.makeManager(serviceUser: Host.User.currentName)
        app.deployer.configureHTTP(config: config)

        try await app.deployer.configureDatabase(config: config)
        await OperationRecovery.repairAbandonedOperations(app: app, config: config)

        app.deployer.configureViews()
        app.deployer.configureMist(config: config)
        try await app.deployer.configurePanel(config: config)

        try app.deployer.configureControl()
    }

    /// Prepares CLI commands with persistence and service access while routing framework logs away from their operator-facing transcripts.
    func useHeadlessRuntime() async throws -> Configuration {

        let config = try Configuration.load()

        try useCLILogging(config: config)

        app.deployer.serviceManager = try config.serviceBackend.makeManager(serviceUser: Host.User.currentName)

        try await app.deployer.configureHeadlessDatabase(config: config)
        await OperationRecovery.repairAbandonedOperations(app: app, config: config)

        return config
    }

    /// Routes non-interactive CLI logs to the shared deployer log while leaving command transcripts on the console.
    func useCLILogging(config: Configuration) throws {

        let logURL = URL(fileURLWithPath: config.deployerLogFilePath)
        let fileHandle = try FileHandle(forWritingTo: logURL)
        fileHandle.seekToEndOfFile()
        app.logger = Logger(label: "deployer.cli") { _ in FileLogHandler(fileHandle: fileHandle) }
    }

}
