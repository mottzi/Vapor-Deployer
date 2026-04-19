import Vapor
import Fluent

extension Deployer {

    static func shouldConfigureServer(for arguments: [String]) -> Bool {

        let commandArguments = arguments.dropFirst()
        guard !commandArguments.contains(where: { $0 == "--help" || $0 == "-h" }) else { return false }

        let command = commandArguments.first { !$0.hasPrefix("-") }
        return command == nil || command == "serve"
    }
    
    func useCommands() {
        app.asyncCommands.use(UpdateCommand(), as: "update")
        app.asyncCommands.use(SetupCommand(), as: "setup")
    }

    func useServer() async throws {

        let config = try Configuration.load()
        try useVariables()
        app.deployer.serviceManager = config.serviceManager.makeManager()
        app.deployer.configureHTTP(config: config)
        try await app.deployer.configureDatabase(config: config)
        app.deployer.configureViews()
        app.deployer.configureMist(config: config)
        try await app.deployer.configurePanel(config: config)
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
        let rowComponent = RowComponent(productName: config.target.name)
        let configComponent = ConfigComponent(using: config)
        let queueComponent = QueueComponent()
        let statusComponent = StatusComponent(
            product: config.target.name,
            status: await serviceManager.status(product: config.target.name)
        )

        useQueue(
            config: config,
            queueState: queueComponent.state,
            onStatusChange: { status in
                await statusComponent.state.set(StatusState(status))
            }
        )
        useWebhook(config: config)
        usePanel(
            config: config,
            row: rowComponent,
            configPopover: configComponent
        )

        try await app.mist.use {
            rowComponent
            statusComponent
            queueComponent
            configComponent
        }
    }

    func createDatabaseDirectory(for dbFile: String) throws {
        
        let dbDirectoryURL = URL(fileURLWithPath: dbFile).deletingLastPathComponent().standardizedFileURL
        let workingDirectoryURL = URL(fileURLWithPath: app.directory.workingDirectory, isDirectory: true).standardizedFileURL
        
        guard dbDirectoryURL != workingDirectoryURL else { return }
        try FileManager.default.createDirectory(at: dbDirectoryURL, withIntermediateDirectories: true)
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
                status: .deployed,
                commitMessage: checkout.commitMessage,
                commitID: checkout.commitID,
                branch: checkout.branch
            )
            
            deployment.isLive = true
            deployment.startedAt = checkout.committedAt
            deployment.finishedAt = checkout.committedAt
            try await deployment.save(on: app.db)
            
        } catch {
            app.logger.warning("Error when seeding initial deployment for '\(config.target.name)': \(error.localizedDescription)")
        }
    }
    
}
