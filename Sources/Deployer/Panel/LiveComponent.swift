import Vapor
import Fluent
import Mist

public struct LiveComponent: Mist.QueryComponent {
    
    public let productName: String
    
    public let models: [any Mist.Model.Type]
    public let template: Template

    public init(productName: String) {
        self.productName = productName
        self.models = [Deployment.self]
        self.template = .file(path: "Deployer/LiveComponent")
    }
    
    public func queryModel(on db: Database) async -> (any Mist.Model)? {
        try? await Deployment.getCurrent(named: productName, on: db)
    }
    
}


