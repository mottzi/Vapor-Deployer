import Vapor
import Fluent
import Mist

extension Deployer {

    static func shouldConfigureServer(for environment: Environment) -> Bool {

        let commandArguments = environment.arguments.dropFirst()
        guard !commandArguments.contains(where: { $0 == "--help" || $0 == "-h" }) else { return false }

        let command = commandArguments.first { !$0.hasPrefix("-") }
        return command == nil || command == "serve"
    }
    
    func useCommands() {
        app.asyncCommands.use(UpdateCommand(), as: "update")
        app.asyncCommands.use(SetupCommand(), as: "setup")
        app.asyncCommands.use(RemoveCommand(), as: "remove")
        app.asyncCommands.use(ConfigCommand(), as: "config")
        app.asyncCommands.use(VersionCommand(), as: "version")
    }

    func useServer() async throws {

        let config = try Configuration.load()
        try useVariables()
        app.deployer.serviceManager = try config.serviceManager.makeManager(serviceUser: UserAccount.currentName())
        app.deployer.configureHTTP(config: config)
        try await app.deployer.configureDatabase(config: config)
        app.deployer.configureViews()
        app.deployer.configureMist(config: config)
        try await app.deployer.configurePanel(config: config)
        try app.deployer.configureAdmin()
    }

}

extension Deployer {

    func configureHTTP(config: Configuration) {
        app.http.server.configuration.port = config.port
        app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))
    }

    func configureDatabase(config: Configuration) async throws {
        try createDatabaseDirectory(for: config.dbFile)
        app.databases.use(.sqlite(.file(config.dbFile)), as: .sqlite)
        app.databases.middleware.use(DeploymentBinaryCleanupMiddleware(target: config.target))
        app.sessions.use(.fluent)
        app.migrations.add(Deployment.migration, SessionRecord.migration)
        try await app.autoMigrate()
        await seedFirstDeployment(config: config)
    }

    func configureViews() {
        app.views.use(.leaf)
    }

    func configureMist(config: Configuration) {
        app.mist.socket.path = config.socketPath.pathComponents
        app.mist.socket.middleware = app.sessions.middleware
        app.mist.socket.shouldUpgrade = { request in
            guard request.session.data["admin_auth"] == "true" else { return nil }
            return HTTPHeaders()
        }
    }

    func configurePanel(config: Configuration) async throws {
        let deploymentRow = DeploymentRow(productName: config.target.name)
        let targetConfig = TargetConfig(using: config)
        let deployerConfig = await DeployerConfig(
            using: config,
            version: DeployerVersion.current()
        )

        let deployerPhase = LiveState(of: DeployerPhase.ready)
        useUpdater(config: config, deployerPhase: deployerPhase)
        let deployerStatus = DeployerStatus(state: deployerPhase, updater: updater)

        let initialStatus = await serviceManager.status(product: config.target.name)
        let badgeState = LiveState(of: StatusState(initialStatus))
        let actionsState = LiveState(of: StatusState(initialStatus))
        let broadcaster = TargetStatusBroadcaster(badge: badgeState, actions: actionsState)

        let targetStatus = TargetStatus(
            product: config.target.name,
            state: badgeState
        )
        let targetStatusActions = TargetStatusActions(
            product: config.target.name,
            state: actionsState,
            broadcaster: broadcaster
        )

        useQueue(
            config: config,
            deployerPhase: deployerPhase,
            onStatusChange: { status in
                await broadcaster.set(StatusState(status))
            }
        )
        useWebhook(config: config)
        usePanel(
            config: config,
            row: deploymentRow,
            targetConfig: targetConfig,
            deployerConfig: deployerConfig,
            deployerStatus: deployerStatus
        )

        try await app.mist.use {
            deploymentRow
            targetStatus
            targetStatusActions
            deployerStatus
            targetConfig
            deployerConfig
        }
    }

    func createDatabaseDirectory(for dbFile: String) throws {
        
        let dbDirectoryPath = URL(fileURLWithPath: dbFile).deletingLastPathComponent().path
        let workingDirectoryPath = app.directory.workingDirectory
        
        guard !PathComparison.isSamePath(dbDirectoryPath, workingDirectoryPath) else { return }
        try FileManager.default.createDirectory(atPath: PathComparison.standardizedPath(dbDirectoryPath), withIntermediateDirectories: true)
    }
    
    func seedFirstDeployment(config: Configuration) async {
        
        do {
            let existingDeploymentCount = try await Deployment.query(on: app.db)
                .filter(\.$product, .equal, config.target.name)
                .count()
            
            guard existingDeploymentCount == 0 else { return }
            
            let checkout = try await Shell.getCurrentCheckout(in: config.target.directory)
            
            let deployment = Deployment(
                product: config.target.name,
                status: .running,
                commitMessage: checkout.commitMessage,
                commitID: checkout.commitID,
                branch: checkout.branch
            )
            
            deployment.isLive = true
            deployment.startedAt = checkout.committedAt
            deployment.finishedAt = checkout.committedAt
            try await deployment.save(on: app.db)
            try await BinaryStore(target: config.target).storeLiveBinary(for: deployment, app: app, manually: false)
            
        } catch {
            app.logger.warning("Error when seeding initial deployment for '\(config.target.name)': \(error.localizedDescription)")
        }
    }
    
}
