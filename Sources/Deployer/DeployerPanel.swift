import Vapor
import Mist

extension Deployer
{
    func usePanel(config: DeployerConfiguration)
    {
        app.get(config.panelRoute)
        { request async throws -> View in
            
            let componentsContext = await DeploymentRow().makeContext(ofAll: request.db)
            let currentDeployment = try? await Deployment.getCurrent(named: config.server.productName, on: request.db)
            
            let statusComponent = currentDeployment.map
            {
                var container = ModelContainer()
                container.add($0, for: "deployment")
                return container
            }
            
            struct DeploymentPanelContext: Encodable
            {
                let components: [ModelContainer]
                let component: ModelContainer?
            }
            
            let context = DeploymentPanelContext(
                components: componentsContext.components,
                component: statusComponent
            )
            
            return try await request.view.render("Deployer/DeploymentPanel", context)
        }
    }
}
