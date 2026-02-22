import Vapor
import Fluent
import Mist

public struct DeployerConfiguration: Sendable
{
    let port: Int
    let dbFile: String
    let buildConfiguration: String
    let server: PipelineConfiguration
    let deployer: PipelineConfiguration
    let mistSocketPath: [PathComponent]
    let panelRoute: [PathComponent]
    let deployerRowComponent: any Mist.InstanceComponent
    let serverRowComponent: any Mist.InstanceComponent
    let statusComponent: any Mist.Component
    
    public init(
        port: Int,
        dbFile: String,
        buildConfiguration: String,
        server: PipelineConfiguration,
        deployer: PipelineConfiguration,
        mistSocketPath: [PathComponent],
        panelRoute: [PathComponent],
        deployerRowComponent: (any Mist.InstanceComponent)? = nil,
        serverRowComponent: (any Mist.InstanceComponent)? = nil,
        statusComponent: (any Mist.Component)? = nil
    ) {
        self.port = port
        self.dbFile = dbFile
        self.buildConfiguration = buildConfiguration
        self.server = server
        self.deployer = deployer
        self.mistSocketPath = mistSocketPath
        self.panelRoute = panelRoute
        self.deployerRowComponent = deployerRowComponent ?? DeploymentRow(productName: deployer.productName)
        self.serverRowComponent = serverRowComponent ?? DeploymentRow(productName: server.productName)
        self.statusComponent = statusComponent ?? DeploymentStatus(productName: server.productName)
    }
}
