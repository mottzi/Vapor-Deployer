import Vapor
import Fluent

extension Application {
    
    public var deployer: Deployer { Deployer(app: self) }
    
}

public struct Deployer: Sendable {
    
    public let app: Application
        
    public func use(config: DeployerConfiguration) async throws {
        
        app.http.server.configuration.port = config.port
        app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))
        
        app.databases.use(.sqlite(.file(config.dbFile)), as: .sqlite/*, isDefault: true*/)
        app.sessions.use(.fluent)
        app.migrations.add(Deployment.migration, SessionRecord.migration)
        try await app.autoMigrate()
        
        app.views.use(.leaf)
        app.mist.socketPath = config.mistSocketPath
        app.mist.socketMiddleware = app.sessions.middleware
        app.mist.shouldUpgrade = { request in
            guard request.session.data["admin_auth"] == "true" else { return nil }
            return HTTPHeaders()
        }
        await app.mist.use(
            config.deployerRowComponent,
            config.serverRowComponent,
            config.statusComponent,
            config.serverStatusComponent,
            config.deployerStatusComponent
        )

        app.deployer.useVariables()
        app.deployer.useQueue(config: config)
        app.deployer.useWebhook(config: config)
        app.deployer.usePanel(config: config)
    }
    
}
