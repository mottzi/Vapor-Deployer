import Vapor
import Mist

public struct DeployerConfiguration: Sendable {
    
    let port: Int
    let dbFile: String
    let serverTarget: TargetConfiguration
    let deployerTarget: TargetConfiguration
    let mistSocketPath: [PathComponent]
    let panelRoute: [PathComponent]
    let deployerRowComponent: any Mist.InstanceComponent
    let serverRowComponent: any Mist.InstanceComponent
    let statusComponent: any Mist.Component
    let serverProductStatusComponent: any Mist.Component      // new
    let deployerProductStatusComponent: any Mist.Component    // new
    
    public init(
        port: Int,
        dbFile: String,
        server: TargetConfiguration,
        deployer: TargetConfiguration,
        mistSocketPath: [PathComponent],
        panelRoute: [PathComponent],
        deployerRowComponent: (any Mist.InstanceComponent)? = nil,
        serverRowComponent: (any Mist.InstanceComponent)? = nil,
        statusComponent: (any Mist.Component)? = nil,
        serverProductStatusComponent: (any Mist.Component)? = nil,     // new
        deployerProductStatusComponent: (any Mist.Component)? = nil    // new
    ) {
        self.port = port
        self.dbFile = dbFile
        self.serverTarget = server
        self.deployerTarget = deployer
        self.mistSocketPath = mistSocketPath
        self.panelRoute = panelRoute
        self.deployerRowComponent = deployerRowComponent ?? PanelDeploymentRow(productName: deployer.productName)
        self.serverRowComponent = serverRowComponent ?? PanelDeploymentRow(productName: server.productName)
        self.statusComponent = statusComponent ?? PanelDeploymentStatus(productName: server.productName)
        self.serverProductStatusComponent = serverProductStatusComponent ?? PanelProductStatus(productName: server.productName)
        self.deployerProductStatusComponent = deployerProductStatusComponent ?? PanelProductStatus(productName: deployer.productName)
    }
    
    func target(for productName: String) -> TargetConfiguration? {
        if productName == serverTarget.productName { return serverTarget }
        if productName == deployerTarget.productName { return deployerTarget }
        return nil
    }
    
}

public struct TargetConfiguration: Sendable {
    
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
