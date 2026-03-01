import Vapor
import Mist

extension Deployer
{
    func usePanel(config: DeployerConfiguration)
    {
        app.get(config.panelRoute)
        { request async throws -> View in
            
            let deployer = await config.deployerRowComponent.makeContext(ofAll: request.db)
            let server = await config.serverRowComponent.makeContext(ofAll: request.db)
            let current = try? await Deployment.getCurrent(named: config.server.productName, on: request.db)
            
            let tables = [
                TableContext(title: "Deployer Pipeline", productName: config.deployer.productName, rows: deployer.components),
                TableContext(title: "Server Pipeline", productName: config.server.productName, rows: server.components)
            ]
            
            let component = current.map {
                var container = ModelContainer()
                container.add($0, for: "deployment")
                return container
            }
            
            let context = DeploymentPanelContext(
                tables: tables,
                component: component
            )
            
            return try await request.view.render("Deployer/DeploymentPanel", context)
        }
    }
    
    struct TableContext: Encodable
    {
        let title: String
        let productName: String
        let rows: [ModelContainer]
    }
    
    struct DeploymentPanelContext: Encodable
    {
        let tables: [TableContext]
        let component: ModelContainer?
    }
}
