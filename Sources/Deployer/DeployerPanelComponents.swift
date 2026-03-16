import Vapor
import Fluent
import Mist

public struct DeployerPanelRow: Mist.InstanceComponent {
    
    let productName: String
    
    public var name: String { "DeploymentRow-\(productName)" }
    public let models: [any Mist.Model.Type] = [Deployment.self]
    public let actions: [any Action] = [DeleteDeploymentAction(), ToggleDeploymentErrorAction()]
    public let template: Template = .file(path: "Deployer/DeploymentRow")
    
    public var defaultState: MistState { ["errorExpanded": .bool(false)] }

    public func allModels(on db: Database) async -> [any Mist.Model]? {
        try? await Deployment.query(on: db)
            .filter(\.$productName == productName)
            .sort(\.$startedAt, .descending)
            .all()
    }
    
    public init(productName: String) { self.productName = productName }
    
}

struct DeleteDeploymentAction: Mist.Action {
    
    let name: String = "delete"
    
    func perform(id: UUID?, state: inout MistState, on db: Database) async -> ActionResult {
        guard let deployment = try? await Deployment.find(id, on: db)
        else { return .failure(message: "Deployment not found") }
        
        guard (try? await deployment.delete(on: db)) != nil
        else { return .failure(message: "Failed to delete deployment") }
        
        return .success()
    }
    
}

struct ToggleDeploymentErrorAction: Mist.Action {
    
    let name: String = "toggleError"
    
    func perform(id: UUID?, state: inout MistState, on db: Database) async -> ActionResult {
        guard let id, let deployment = try? await Deployment.find(id, on: db)
        else { return .failure(message: "Deployment not found") }
        
        guard deployment.errorMessage != nil
        else { return .failure(message: "No error to display") }
        
        let current = state["errorExpanded"]?.bool ?? false
        state["errorExpanded"] = .bool(!current)
        return .success()
    }

}

public struct DeployerPanelStatus: Mist.QueryComponent {
    
    public let name = "DeploymentStatus"
    public let models: [any Mist.Model.Type] = [Deployment.self]
    public let template: Template = .file(path: "Deployer/DeploymentStatus")
    public let productName: String

    public func queryModel(on db: Database) async -> (any Mist.Model)? {
        try? await Deployment.getCurrent(named: productName, on: db)
    }
    
    public init(productName: String) {
        self.productName = productName
    }
    
}

public struct ProductStatusComponent: Mist.QueryComponent {

    public var name: String { "ProductStatus-\(productName)" }
    public let models: [any Mist.Model.Type] = [ProductStatus.self]
    public let template: Template = .file(path: "Deployer/ProductStatus")
    public let productName: String
    public let actions: [any Mist.Action]

    public func queryModel(on db: Database) async -> (any Mist.Model)? {
        try? await ProductStatus.query(on: db)
            .filter(\.$productName == productName)
            .first()
    }

    public init(productName: String) {
        self.productName = productName
        self.actions = [
            ProductRestartAction(productName: productName),
            ProductStopAction(productName: productName)
        ]
    }

}

struct ProductRestartAction: Mist.Action {

    let name = "restart"
    let productName: String

    func perform(id: UUID?, state: inout MistState, on db: Database) async -> ActionResult {
        do {
            try await SupervisorControl.restart(program: productName)
            try await ProductStatus.upsert(productName: productName, isRunning: true, on: db)
            return .success()
        } catch {
            return .failure(message: error.localizedDescription)
        }
    }

}

struct ProductStopAction: Mist.Action {

    let name = "stop"
    let productName: String

    func perform(id: UUID?, state: inout MistState, on db: Database) async -> ActionResult {
        do {
            try await SupervisorControl.stop(program: productName)
            try await ProductStatus.upsert(productName: productName, isRunning: false, on: db)
            return .success()
        } catch {
            return .failure(message: error.localizedDescription)
        }
    }

}
