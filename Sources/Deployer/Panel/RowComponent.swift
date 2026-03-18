import Vapor
import Fluent
import Mist

public struct RowComponent: Mist.InstanceComponent {
    
    let productName: String
    
    public let name: String
    public let models: [any Mist.Model.Type]
    public let actions: [any Mist.Action]
    public let template: Template
    public let defaultState: MistState
    
    public init(productName: String) {
        self.productName = productName
        self.name = "RowComponent-\(productName)"
        self.defaultState = ["errorExpanded": .bool(false)]
        self.models = [Deployment.self]
        self.actions = [DeleteAction(), ToggleErrorAction()]
        self.template = .file(path: "Deployer/RowComponent")
    }
    
    public func allModels(on db: Database) async -> [any Mist.Model]? {
        try? await Deployment.query(on: db)
            .filter(\.$productName == productName)
            .sort(\.$startedAt, .descending)
            .all()
    }
    
}

extension RowComponent {
    
    struct DeleteAction: Mist.Action {
        
        let name: String = "delete"
        
        func perform(id: UUID?, state: inout MistState, on db: Database) async -> ActionResult {
            
            guard let deployment = try? await Deployment.find(id, on: db) else { return .failure(message: "Deployment not found") }
            guard (try? await deployment.delete(on: db)) != nil else { return .failure(message: "Failed to delete deployment") }
            return .success()
        }
        
    }
    
    struct ToggleErrorAction: Mist.Action {
        
        let name: String = "toggleError"
        
        func perform(id: UUID?, state: inout MistState, on db: Database) async -> ActionResult {
            
            guard let id else { return .failure(message: "No ID found") }
            guard let deployment = try? await Deployment.find(id, on: db) else { return .failure(message: "Deployment not found") }
            guard deployment.errorMessage != nil else { return .failure(message: "No error to display") }
            
            let current = state["errorExpanded"]?.bool ?? false
            state["errorExpanded"] = .bool(!current)
            return .success()
        }

    }
    
}
