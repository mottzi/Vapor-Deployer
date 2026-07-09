import Vapor

extension Application {
    
    var deployer: Deployer { Deployer(app: self) }
    
}
 
@main struct Deployer {
    
    let app: Application
    
    static func main() async throws {
        
        var env = try Environment.detect()
        
        LoggingSystem.bootstrap(
            fragment: timestampDefaultLoggerFragment(),
            console: Terminal(),
            level: try Logger.Level.detect(from: &env)
        )
        
        let app = try await Application.make(env)
        app.deployer.useCommands()

        let configuresServer = shouldConfigureServer(for: env)

        if configuresServer {
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
            if !configuresServer {
                app.console.error(error.localizedDescription)
            }

            try? await app.asyncShutdown()
            exit(1)
        }
        
        try await app.asyncShutdown()
    }
    
}
