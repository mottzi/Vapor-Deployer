import Vapor
import Fluent
import Mist

public struct DeployerConfiguration: Sendable
{
    let port: Int
    let dbFile: String
    let buildConfiguration: String
    let serverConfig: PipelineConfiguration
    let deployerConfig: PipelineConfiguration
    let mistSocketPath: [PathComponent]
    let panelRoute: [PathComponent]
    let rowComponent: any Mist.Component
    let statusComponent: any Mist.Component
    
    public init(
        port: Int,
        dbFile: String,
        buildConfiguration: String,
        serverConfig: PipelineConfiguration,
        deployerConfig: PipelineConfiguration,
        mistSocketPath: [PathComponent],
        panelRoute: [PathComponent],
        rowComponent: any Mist.Component = DeploymentRow(),
        statusComponent: any Mist.Component = DeploymentStatus()
    ) {
        self.port = port
        self.dbFile = dbFile
        self.buildConfiguration = buildConfiguration
        self.serverConfig = serverConfig
        self.deployerConfig = deployerConfig
        self.mistSocketPath = mistSocketPath
        self.panelRoute = panelRoute
        self.rowComponent = rowComponent
        self.statusComponent = statusComponent
    }
}
