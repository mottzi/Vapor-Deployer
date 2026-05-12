import Vapor
import Fluent
import Mist

struct RowComponent: InstanceComponent {
    
    let productName: String
    
    let name: String
    let models: [any Mist.Model.Type] = [Deployment.self]
    let actions: [any Action]
    let template: any Template = LeafTemplate.file("Deployer/RowComponent")
    let defaultState: ComponentState = ["detailsExpanded": .bool(false)]

    static func name(for productName: String) -> String {
        "RowComponent-\(productName)"
    }
    
    init(productName: String) {
        self.productName = productName
        self.name = Self.name(for: productName)
        self.actions = [
            DeployAction(productName: productName),
            SaveBinaryAction(productName: productName),
            RestoreBinaryAction(productName: productName),
            DeleteAction(productName: productName),
            ToggleDetailsAction(productName: productName)
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
            guard let deployment = await loadDeployment(id: targetID, product: productName, app: app) else { return .failure("Deployment not found") }
            guard deployment.canBeDeployed else { return .failure("Deployments already in progress cannot be started again") }
            guard !deployment.hasSavedBinary else { return .failure("Deployments with saved binaries must be restored, not built") }
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
            guard let targetID else { return .failure("Deployment not found") }
            guard let deployment = await loadDeployment(id: targetID, product: productName, app: app) else { return .failure("Deployment not found") }
            do { try await deployment.delete(on: app.db) }
            catch { app.logger.error("\(MistError.databaseFetchFailed("Deployment delete id=\(deployment.id?.uuidString ?? "nil")", error))"); return .failure("Failed to delete deployment") }
            return .success()
        }

    }

    struct SaveBinaryAction: Action {

        let name: String = "saveBinary"
        let productName: String

        func perform(targetID: UUID?, state: inout ComponentState, app: Application) async -> ActionResult {
            guard let targetID else { return .failure("No ID found") }
            guard let deployment = await loadDeployment(id: targetID, product: productName, app: app) else { return .failure("Deployment not found") }
            guard deployment.canSaveBinary else { return .failure("This deployment already has a saved binary or cannot be built right now") }
            let target = app.deployer.queue.config.target
            let store = BinaryStore(target: target)
            guard !store.hasBinary(for: deployment) else { return .failure("This deployment already has a saved binary") }
            return switch await app.deployer.queue.saveBinary(deployment: deployment, target: target) {
            case .started: .success("Binary save started")
            case .queueBusy: .failure("A deployment is already running")
            case .failure(let message): .failure(message)
            }
        }

    }

    struct RestoreBinaryAction: Action {

        let name: String = "restoreBinary"
        let productName: String

        func perform(targetID: UUID?, state: inout ComponentState, app: Application) async -> ActionResult {
            guard let targetID else { return .failure("No ID found") }
            guard let deployment = await loadDeployment(id: targetID, product: productName, app: app) else { return .failure("Deployment not found") }
            guard deployment.canRestoreBinary else { return .failure("This deployment does not have a saved binary or cannot be restored right now") }
            let target = app.deployer.queue.config.target
            let store = BinaryStore(target: target)
            guard store.hasBinary(for: deployment) else { return .failure("Saved binary not found on disk") }
            return switch await app.deployer.queue.restoreBinary(deployment: deployment, target: target) {
            case .started: .success("Binary restore started")
            case .queueBusy: .failure("A deployment is already running")
            case .failure(let message): .failure(message)
            }
        }

    }

    struct ToggleDetailsAction: Action {

        let name: String = "toggleDetails"
        let productName: String

        func perform(targetID: UUID?, state: inout ComponentState, app: Application) async -> ActionResult {
            guard let targetID else { return .failure("No ID found") }
            guard let deployment = await loadDeployment(id: targetID, product: productName, app: app) else { return .failure("Deployment not found") }
            guard deployment.hasDetails else { return .failure("No details to display") }
            let current = state["detailsExpanded"]?.bool ?? false
            state["detailsExpanded"] = .bool(!current)
            return .success()
        }

    }

}

func loadDeployment(id: UUID, product: String, app: Application) async -> Deployment? {
    do {
        guard let deployment = try await Deployment.find(id, on: app.db) else { return nil }
        guard deployment.product == product else { return nil }
        return deployment
    } catch {
        app.logger.error("\(MistError.databaseFetchFailed("Deployment id=\(id)", error))")
        return nil
    }
}
