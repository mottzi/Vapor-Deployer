import Fluent
import Mist
import Vapor

public struct DeploymentStatus: QueryComponent
{
    public let models: [any Mist.Model.Type]
    public let template: Template

    public func queryModel(on db: Database) async -> (any Mist.Model)?
    {
        return try? await Deployment.getCurrent(named: "Mottzi", on: db)
    }
    
    public init()
    {
        self.models = [Deployment.self]
        self.template = .file(path: "Deployer/DeploymentStatus")
    }
}
