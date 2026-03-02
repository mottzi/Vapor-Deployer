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
            let current = try? await Deployment.getCurrent(named: config.serverTarget.productName, on: request.db)
            
            let context = DeploymentPanelContext(
                tables: [
                    TableContext(
                        title: config.deployerTarget.productName.capitalized,
                        productName: config.deployerTarget.productName,
                        rows: deployer.components
                    ),
                    TableContext(
                        title: config.serverTarget.productName.capitalized,
                        productName: config.serverTarget.productName,
                        rows: server.components
                    )
                ],
                component: current.map {
                    var container = ModelContainer()
                    container.add($0, for: "deployment")
                    return container
                }
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
