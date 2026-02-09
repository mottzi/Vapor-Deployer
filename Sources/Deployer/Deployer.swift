import Vapor
import Fluent
import Mist

extension Application
{
    public struct Deployer: Sendable
    {
        public let app: Application
        
        public func use(config: Configuration) async throws
        {
            app.http.server.configuration.port = config.port
            app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))
            
            app.databases.use(.sqlite(.file(config.dbFile)), as: .sqlite)
            app.migrations.add(Deployment.Table())
            try await app.autoMigrate()
            
            app.views.use(.leaf)
            app.mist.socketPath = config.mistSocketPath
            await app.mist.use(config.rowComponent, config.statusComponent)
            
            app.environment.useVariables()
            app.deployer.useWebhook(config: config, on: app)
            app.useCommand(config: config)
            app.usePanel(config: config)
        }
    }
    
    public var deployer: Deployer { Deployer(app: self) }
}

extension Application.Deployer
{
    public struct Configuration: Sendable
    {
        var port: Int
        var dbFile: String
        var buildConfiguration: String
        var serverConfig: Pipeline.Configuration
        var deployerConfig: Pipeline.Configuration
        var mistSocketPath: [PathComponent]
        var panelRoute: [PathComponent]
        var rowComponent: any Mist.Component
        var statusComponent: any Mist.Component
        
        public static var standard: Configuration
        {
            Configuration(
                port: 8081,
                dbFile: "deploy/deployer.db",
                buildConfiguration: "debug",
                serverConfig: Pipeline.Configuration(
                    productName: "mottzi",
                    workingDirectory: "/home/vapor/mottzi",
                    buildConfiguration: "debug",
                    pusheventPath: ["pushevent", "mottzi"]
                ),
                deployerConfig: Pipeline.Configuration(
                    productName: "mottzi-deployer",
                    workingDirectory: "/home/vapor/mottzi-deployer",
                    buildConfiguration: "debug",
                    pusheventPath: ["pushevent", "mottzi-deployer"]
                ),
                mistSocketPath: ["deployer", "ws"],
                panelRoute: ["deployer"],
                rowComponent: DeploymentRow(),
                statusComponent: DeploymentStatus()
            )
        }
    }
}

extension Application.Deployer
{
    final class Storage: @unchecked Sendable
    {
        init() {}
//        var socketPath: [PathComponent]?
    }
    
    private struct Key: StorageKey { typealias Value = Storage }
    
    var _storage: Storage
    {
        if let existing = app.storage[Key.self] { return existing }
        let new = Storage()
        app.storage[Key.self] = new
        return new
    }
}

//extension Application.Deployer
//{
//    private struct SocketPathKey: LockKey {}
//
//    var _socketPath: [PathComponent]
//    {
//        get
//        {
//            return app.locks.lock(for: SocketPathKey.self).withLock
//            {
//                return _storage.socketPath ?? ["mist", "ws"]
//            }
//        }
//        nonmutating set
//        {
//            app.locks.lock(for: SocketPathKey.self).withLock
//            {
//                _storage.socketPath = newValue
//            }
//        }
//    }
//}
