import Mist
import Vapor

extension Application
{
    func useCommand(config: Deployer.Configuration)
    {
        self.useCommandRoute(config: config)
        
        self.asyncCommands.use(Deployer.Command(config: config), as: "deploy")
    }
    
    func useCommandRoute(config: Deployer.Configuration)
    {
        self.post("\(config.deployerConfig.productName)/deploy")
        { request async throws -> String in

            guard let providedSecret = request.headers.first(name: "X-Deploy-Secret"),
                  let expectedSecret = Environment.get(Environment.Variables.DEPLOY_SECRET.rawValue)
            else { throw Abort(.unauthorized, reason: "Could not obtain secrets to compare.") }

            guard providedSecret == expectedSecret 
            else { throw Abort(.unauthorized, reason: "Secrets didn't match.") }
            
            Task.detached
            {
                let pipeline = Deployer.Pipeline(config: config.deployerConfig)
                await pipeline.deploy(message: "[CLI] \(config.deployerConfig.productName)", on: self)
            }

            return "Started deployment pipeline"
        }
    }
}
