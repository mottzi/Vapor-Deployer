import Vapor
import Fluent
import Mist

public struct DeploymentRow: Mist.InstanceComponent
{
    public let models: [any Mist.Model.Type]
    public let actions: [any Action]
    public let template: Template
    
    public var defaultState: MistState
    {
        ["errorExpanded": .bool(false)]
    }

    public func allModels(on db: Database) async -> [any Mist.Model]?
    {
        return try? await Deployment.query(on: db)
            .sort(\.$startedAt, .descending)
            .all()
    }
    
    public init()
    {
        self.models = [Deployment.self]
        self.actions = [DeleteDeploymentAction(), ToggleDeploymentErrorAction()]
        self.template = .file(path: "Deployer/DeploymentRow")
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

