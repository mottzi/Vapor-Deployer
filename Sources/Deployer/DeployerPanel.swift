import Vapor
import Mist

extension Deployer
{
    func usePanel(config: DeployerConfiguration)
    {
        app.get(config.panelRoute)
        { request async throws -> View in
            
            let deployerContext = await config.deployerRowComponent.makeContext(ofAll: request.db)
            let serverContext = await config.serverRowComponent.makeContext(ofAll: request.db)
            let currentDeployment = try? await Deployment.getCurrent(named: config.server.productName, on: request.db)
            
            let statusComponent = currentDeployment.map
            {
                var container = ModelContainer()
                container.add($0, for: "deployment")
                return container
            }
            
            struct TableContext: Encodable {
                let title: String
                let productName: String
                let rows: [ModelContainer]
            }
            
            struct DeploymentPanelContext: Encodable
            {
                let tables: [TableContext]
                let component: ModelContainer?
            }
            
            // Pass the array of tables to Leaf
            let context = DeploymentPanelContext(
                tables: [
                    TableContext(title: "Deployer Pipeline", productName: config.deployer.productName, rows: deployerContext.components),
                    TableContext(title: "Server Pipeline", productName: config.server.productName, rows: serverContext.components)
                ],
                component: statusComponent
            )
            
            return try await request.view.render("Deployer/DeploymentPanel", context)
        }
    }
}
