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
        self.help = "Pulls, builds, moves and restarts \(config.deployerConfig.productName)."
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
        self.app.post("\(config.panelRoute)/deploy")
        { request async throws -> String in

            guard let providedSecret = request.headers.first(name: "X-Deploy-Secret"),
                  let expectedSecret = Environment.get(DeployerVariables.DEPLOY_SECRET.rawValue)
            else { throw Abort(.unauthorized, reason: "Could not obtain secrets to compare.") }

            guard providedSecret == expectedSecret
            else { throw Abort(.unauthorized, reason: "Secrets didn't match.") }
            
            Task.detached
            {
                let pipeline = DeployerPipeline(pipelineConfig: config.deployerConfig, deployerConfig: config)
                await pipeline.deploy(message: "[CLI] \(config.deployerConfig.productName)", on: app)
            }

            return "Started deployment pipeline"
        }
    }
}
