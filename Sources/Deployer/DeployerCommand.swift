import Vapor

extension Deployer
{
    func useCommand(config: DeployerConfiguration)
    {
        let command = DeployCommand(config: config, app: app)
        command.useRoute(config: config)
        self.app.asyncCommands.use(command, as: "deploy")
    }
}

struct DeployCommand: AsyncCommand
{
    struct Signature: CommandSignature {}

    let app: Application
    let config: DeployerConfiguration
    let help: String
    
    init(config: DeployerConfiguration, app: Application)
    {
        self.app = app
        self.config = config
        self.help = "Pulls, builds, moves and restarts \(config.deployer.productName)."
    }

    func run(using context: CommandContext, signature: Signature) async throws
    {
        let uri = URI(string: "http://localhost:\(config.port)/\(config.panelRoute)/deploy")

        let response = try await context.application.client.post(uri)
        {
            $0.headers.add(
                name: "X-Deploy-Secret",
                value: DeployerVariables.DEPLOY_SECRET.value
            )
        }

        context.console.print("Deployer Response: \(response.status).")
    }
}

extension DeployCommand
{
    func useRoute(config: DeployerConfiguration)
    {
        app.post("\(config.panelRoute)/deploy")
        { request async throws -> String in

            guard let providedSecret = request.headers.first(name: "X-Deploy-Secret"),
                  let expectedSecret = Environment.get(DeployerVariables.DEPLOY_SECRET.rawValue)
            else { throw Abort(.unauthorized, reason: "Could not obtain secrets to compare.") }

            guard providedSecret == expectedSecret
            else { throw Abort(.unauthorized, reason: "Secrets didn't match.") }
            
            Task.detached
            {
                let pipeline = DeploymentPipeline(pipeline: config.deployer, deployer: config, on: app)
                await pipeline.deploy(message: "[CLI] \(config.deployer.productName)")
            }

            return "Started deployment pipeline"
        }
    }
}
