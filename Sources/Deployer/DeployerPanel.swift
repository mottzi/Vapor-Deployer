import Vapor
import Mist

typealias MistModelContainer = Mist.ModelContainer

extension Application
{
    func usePanel(config: DeployerConfiguration)
    {
        self.get(config.panelRoute)
        { request async throws -> View in
            
            let componentsContext = await DeploymentRow().makeContext(ofAll: request.db)
            let currentDeployment = try? await Deployment.getCurrent(named: config.serverConfig.productName, on: request.db)
            
            let statusComponent = currentDeployment.map
            {
                var container = MistModelContainer()
                container.add($0, for: "deployment")
                return container
            }
            
            struct DeploymentPanelContext: Encodable
            {
                let components: [MistModelContainer]
                let component: MistModelContainer?
            }
            
            let context = DeploymentPanelContext(
                components: componentsContext.components,
                component: statusComponent
            )
            
            return try await request.view.render("Deployer/DeploymentPanel", context)
        }
    }
}
