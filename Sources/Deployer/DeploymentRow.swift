import Vapor
import Fluent
import Mist

public struct DeploymentRow: Mist.InstanceComponent
{
    let productName: String
    
    public var name: String { "DeploymentRow-\(productName)" }
    
    public let models: [any Mist.Model.Type] = [Deployment.self]
    public let actions: [any Action] = [DeleteDeploymentAction(), ToggleDeploymentErrorAction()]
    public let template: Template = .file(path: "Deployer/DeploymentRow")
    
    public var defaultState: MistState
    {
        ["errorExpanded": .bool(false)]
    }

    public func allModels(on db: Database) async -> [any Mist.Model]?
    {
        return try? await Deployment.query(on: db)
            .filter(\.$productName == productName)
            .sort(\.$startedAt, .descending)
            .all()
    }
    
    public init(productName: String)
    {
        self.productName = productName
    }
}

struct DeleteDeploymentAction: Mist.Action
{
    let name: String = "delete"
    
    func perform(id: UUID?, state: inout MistState, on db: Database) async -> ActionResult
    {
        guard let deployment = try? await Deployment.find(id, on: db)
        else { return .failure(message: "Deployment not found") }
        
        guard (try? await deployment.delete(on: db)) != nil
        else { return .failure(message: "Failed to delete deployment") }
        
        return .success()
    }
}

struct ToggleDeploymentErrorAction: Mist.Action
{
    let name: String = "toggleError"
    
    func perform(id: UUID?, state: inout MistState, on db: Database) async -> ActionResult
    {
        guard let id, let deployment = try? await Deployment.find(id, on: db) else
        {
            return .failure(message: "Deployment not found")
        }
        
        guard deployment.errorMessage != nil else
        {
            return .failure(message: "No error to display")
        }
        
        let current = state["errorExpanded"]?.bool ?? false
        state["errorExpanded"] = .bool(!current)
        return .success()
    }
}

