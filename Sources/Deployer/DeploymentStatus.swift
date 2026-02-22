import Fluent
import Mist
import Vapor

public struct DeploymentStatus: QueryComponent
{
    public let models: [any Mist.Model.Type] = [Deployment.self]
    public let template: Template = .file(path: "Deployer/DeploymentStatus")
    public let productName: String

    public func queryModel(on db: Database) async -> (any Mist.Model)?
    {
        return try? await Deployment.getCurrent(named: productName, on: db)
    }
    
    public init(productName: String)
    {
        self.productName = productName
    }
}
