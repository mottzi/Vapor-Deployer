import Vapor

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
        
        await app.mist.use(
            config.deployerRowComponent,
            config.serverRowComponent,
            config.statusComponent
        )
    
        app.deployer.useQueue(config: config)
        app.deployer.useVariables()
        app.deployer.useWebhook(config: config)
        app.deployer.useCommand(config: config)
        app.deployer.usePanel(config: config)
    }
}

extension Application
{
    public var deployer: Deployer { Deployer(app: self) }

    var _queue: DeploymentQueue?
    {
        get { storage[DeploymentQueueKey.self] }
        set { storage[DeploymentQueueKey.self] = newValue }
    }

    struct DeploymentQueueKey: StorageKey { typealias Value = DeploymentQueue }
}

extension Deployer
{
    var queue: DeploymentQueue
    {
        if let queue = app._queue { return queue }
        fatalError("Queue not initialized!")
    }
    
    func useQueue(config: DeployerConfiguration)
    {
        app._queue = DeploymentQueue(app: app, config: config)
    }
}
