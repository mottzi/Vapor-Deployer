import Vapor
import Mist

public struct DeployerConfiguration: Sendable
{
    let port: Int
    let dbFile: String
    let server: TargetConfiguration
    let deployer: TargetConfiguration
    let mistSocketPath: [PathComponent]
    let panelRoute: [PathComponent]
    let deployerRowComponent: any Mist.InstanceComponent
    let serverRowComponent: any Mist.InstanceComponent
    let statusComponent: any Mist.Component
    
    public init(
        port: Int,
        dbFile: String,
        server: TargetConfiguration,
        deployer: TargetConfiguration,
        mistSocketPath: [PathComponent],
        panelRoute: [PathComponent],
        deployerRowComponent: (any Mist.InstanceComponent)? = nil,
        serverRowComponent: (any Mist.InstanceComponent)? = nil,
        statusComponent: (any Mist.Component)? = nil
    ) {
        self.port = port
        self.dbFile = dbFile
        self.server = server
        self.deployer = deployer
        self.mistSocketPath = mistSocketPath
        self.panelRoute = panelRoute
        self.deployerRowComponent = deployerRowComponent ?? DeployerPanelRow(productName: deployer.productName)
        self.serverRowComponent = serverRowComponent ?? DeployerPanelRow(productName: server.productName)
        self.statusComponent = statusComponent ?? DeployerPanelStatus(productName: server.productName)
    }
    
    func target(for productName: String) -> TargetConfiguration?
    {
        if productName == server.productName { return server }
        if productName == deployer.productName { return deployer }
        return nil
    }
}

public struct TargetConfiguration: Sendable
{
    let productName: String
    let workingDirectory: String
    let buildMode: String
    var pusheventPath: [PathComponent]
    
    public init(
        productName: String,
        workingDirectory: String,
        buildMode: String,
        pusheventPath: [PathComponent]
    ) {
        self.productName = productName
        self.workingDirectory = workingDirectory
        self.buildMode = buildMode
        self.pusheventPath = pusheventPath
    }
}
