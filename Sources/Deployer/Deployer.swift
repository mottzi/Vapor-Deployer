import Vapor
import Fluent
import Foundation

extension Application {
    
    var deployer: Deployer { Deployer(app: self) }
    
}

@main struct Deployer: Sendable {
    
    let app: Application
        
    func useCommands() {
        app.asyncCommands.use(UpdateCommand(), as: "update")
    }

    func useServer() async throws {
        
        let config = try Configuration.load()
        app.deployer.serviceManager = config.serviceManager.makeManager()
        app.deployer.configureHTTP(config: config)
        try await app.deployer.configureDatabase(config: config)
        app.deployer.configureViews()
        app.deployer.configureMist(config: config)
        try await app.deployer.configurePanel(config: config)
    }
    
}

extension Deployer {
    
    static func main() async throws {
        
        var env = try Environment.detect()
        try LoggingSystem.bootstrap(from: &env)
        let app = try await Application.make(env)
        
        app.deployer.useCommands()

        if app.deployer.shouldServe() {
            do {
                try await app.deployer.useServer()
            } catch {
                app.logger.report(error: error)
                try? await app.asyncShutdown()
                exit(1)
            }
        }

        do {
            try await app.execute()
        } catch {
            try? await app.asyncShutdown()
            exit(1)
        }
        
        try await app.asyncShutdown()
    }
    
}
