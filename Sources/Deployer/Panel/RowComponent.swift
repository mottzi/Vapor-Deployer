import Vapor
import Mist
import Fluent

struct RowComponent: InstanceComponent {
    
    let productName: String
    
    let name: String
    let models: [any Mist.Model.Type] = [Deployment.self]
    let actions: [any Action]
    let template: any Template = LeafTemplate.file("Deployer/RowComponent")
    let defaultState: ComponentState = ["errorExpanded": .bool(false)]
    
    init(productName: String) {
        self.productName = productName
        self.name = "RowComponent-\(productName)"
        self.actions = [
            DeployAction(productName: productName),
            DeleteAction(productName: productName),
            ToggleErrorAction(productName: productName)
        ]
    }
    
    func allModels(on db: Database) async throws -> [any Mist.Model] {
        try await Deployment.query(on: db)
            .filter(\.$product == productName)
            .sort(\.$startedAt, .descending)
            .all()
    }
    
}

extension RowComponent {
    
    struct DeployAction: Action {
        
        let name: String = "deploy"
        let productName: String
        
        func perform(targetID: UUID?, state: inout ComponentState, app: Application) async -> ActionResult {

            guard let targetID else { return .failure("No ID found") }
            let deployment: Deployment?
            do { deployment = try await Deployment.find(targetID, on: app.db) }
            catch { app.logger.error("\(MistError.databaseFetchFailed("Deployment id=\(targetID)", error))"); return .failure("Database error looking up deployment") }
            guard let deployment else { return .failure("Deployment not found") }
            guard deployment.product == productName else { return .failure("Deployment not found") }
            guard deployment.canBeDeployed else { return .failure("Deployments already in progress cannot be started again") }
            let target = app.deployer.queue.config.target

            return switch await app.deployer.queue.deploy(deployment: deployment, target: target) {
            case .started: .success("Deployment started")
            case .queueBusy: .failure("A deployment is already running")
            case .failure(let message): .failure(message)
            }
        }
        
    }
    
    struct DeleteAction: Action {
        
        let name: String = "delete"
        let productName: String
        
        func perform(targetID: UUID?, state: inout ComponentState, app: Application) async -> ActionResult {

            let deployment: Deployment?
            do { deployment = try await Deployment.find(targetID, on: app.db) }
            catch { app.logger.error("\(MistError.databaseFetchFailed("Deployment id=\(targetID?.uuidString ?? "nil")", error))"); return .failure("Database error looking up deployment") }
            guard let deployment else { return .failure("Deployment not found") }
            guard deployment.product == productName else { return .failure("Deployment not found") }
            do { try await deployment.delete(on: app.db) }
            catch { app.logger.error("\(MistError.databaseFetchFailed("Deployment delete id=\(deployment.id?.uuidString ?? "nil")", error))"); return .failure("Failed to delete deployment") }
            return .success()
        }
        
    }
    
    struct ToggleErrorAction: Action {
        
        let name: String = "toggleError"
        let productName: String
        
        func perform(targetID: UUID?, state: inout ComponentState, app: Application) async -> ActionResult {

            guard let targetID else { return .failure("No ID found") }
            let deployment: Deployment?
            do { deployment = try await Deployment.find(targetID, on: app.db) }
            catch { app.logger.error("\(MistError.databaseFetchFailed("Deployment id=\(targetID)", error))"); return .failure("Database error looking up deployment") }
            guard let deployment else { return .failure("Deployment not found") }
            guard deployment.product == productName else { return .failure("Deployment not found") }
            guard deployment.errorMessage != nil else { return .failure("No error to display") }
            
            let current = state["errorExpanded"]?.bool ?? false
            state["errorExpanded"] = .bool(!current)
            return .success()
        }

    }
    
}
