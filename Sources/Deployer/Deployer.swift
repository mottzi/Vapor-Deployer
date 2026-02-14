import Vapor
import Fluent
import Mist

extension Application
{
    public var deployer: Deployer { Deployer(app: self) }
}

public struct Deployer: Sendable
{
    public let app: Application
    
    public func use(config: DeployerConfiguration) async throws
    {
        app.http.server.configuration.port = config.port
        app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))
        
        app.databases.use(.sqlite(.file(config.dbFile)), as: .sqlite)
        app.migrations.add(Deployment.Table())
        try await app.autoMigrate()
        
        app.views.use(.leaf)
        app.mist.socketPath = config.mistSocketPath
        await app.mist.use(config.rowComponent, config.statusComponent)
        
        app.deployer.useVariables()
        app.deployer.useWebhook(config: config)
        app.deployer.useCommand(config: config)
        app.deployer.usePanel(config: config)
    }
}
