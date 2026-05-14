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
            RemoveBinaryAction(productName: productName),
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
            
            guard let targetID,
                  let deployment = await loadDeployment(id: targetID, product: productName, app: app),
                  deployment.canBuild
            else { return .failure("Deployment not found or can't be built.") }
            
            let result = await app.deployer.queue.deploy(
                deployment: deployment,
                target: app.deployer.queue.config.target
            )
            
            return switch result {
            case .started:
                .success("Deployment started")
            case .queueBusy:
                .failure("A deployment is already running")
            case .failure(let message):
                .failure(message)
            }
        }

    }

    struct DeleteAction: Action {

        let name: String = "delete"
        let productName: String

        func perform(targetID: UUID?, state: inout ComponentState, app: Application) async -> ActionResult {
            
            guard let targetID,
                  let deployment = await loadDeployment(id: targetID, product: productName, app: app)
            else { return .failure("Deployment not found") }
            
            guard !deployment.isLive else {
                return .failure("Cannot delete the active live deployment")
            }
            
            do {
                try await deployment.delete(on: app.db)
            }
            catch {
                let error = MistError.databaseFetchFailed(
                    "Deployment delete id=\(deployment.id?.uuidString ?? "nil")",
                    error
                )
                app.logger.error("\(error)")
                return .failure("Failed to delete deployment")
            }
            
            return .success()
        }

    }

    struct SaveBinaryAction: Action {

        let name: String = "saveBinary"
        let productName: String

        func perform(targetID: UUID?, state: inout ComponentState, app: Application) async -> ActionResult {
            
            guard let targetID,
                  let deployment = await loadDeployment(id: targetID, product: productName, app: app),
                  deployment.canBuild
            else { return .failure("Deployment not found or can't be built.") }
            
            let target = app.deployer.queue.config.target
            let store = BinaryStore(target: target)
            guard !store.hasBinary(for: deployment)
            else { return .failure("This deployment already has a saved binary") }
            
            let result = await app.deployer.queue.saveBinary(
                deployment: deployment,
                target: target
            )
            
            return switch result {
            case .started:
                .success("Binary save started")
            case .queueBusy:
                .failure("A deployment is already running")
            case .failure(let message):
                .failure(message)
            }
        }

    }

    struct RestoreBinaryAction: Action {

        let name: String = "restoreBinary"
        let productName: String

        func perform(targetID: UUID?, state: inout ComponentState, app: Application) async -> ActionResult {
            
            guard let targetID,
                  let deployment = await loadDeployment(id: targetID, product: productName, app: app),
                  deployment.canRestoreBinary
            else { return .failure("Deployment not found or can't restore its binary.") }
            
            let target = app.deployer.queue.config.target
            let store = BinaryStore(target: target)
            guard store.hasBinary(for: deployment)
            else { return .failure("Saved binary not found on disk") }
            
            let result = await app.deployer.queue.restoreBinary(
                deployment: deployment,
                target: target
            )
            
            return switch result {
            case .started:
                .success("Binary restore started")
            case .queueBusy:
                .failure("A deployment is already running")
            case .failure(let message):
                .failure(message)
            }
        }

    }

    struct RemoveBinaryAction: Action {

        let name: String = "removeBinary"
        let productName: String

        func perform(targetID: UUID?, state: inout ComponentState, app: Application) async -> ActionResult {
            
            guard let targetID,
                  let deployment = await loadDeployment(id: targetID, product: productName, app: app),
                  deployment.hasSavedBinary
            else { return .failure("Deployment not found or doesn't have a saved binary.") }
            
            let target = app.deployer.queue.config.target
            let store = BinaryStore(target: target)
            guard store.hasBinary(for: deployment)
            else { return .failure("Saved binary not found on disk") }
            
            do {
                try store.deleteBinary(for: deployment)
                deployment.binarySizeMB = nil
                deployment.isManuallySaved = false
                deployment.status = .pushed
                try await deployment.save(on: app.db)
            }
            catch {
                let mistError = MistError.databaseFetchFailed(
                    "Binary delete id=\(deployment.id?.uuidString ?? "nil")",
                    error
                )
                app.logger.error("\(mistError)")
                return .failure("Failed to remove binary")
            }
            
            return .success()
        }

    }

    struct ToggleDetailsAction: Action {

        let name: String = "toggleDetails"
        let productName: String

        func perform(targetID: UUID?, state: inout ComponentState, app: Application) async -> ActionResult {
            
            guard let targetID,
                  let deployment = await loadDeployment(id: targetID, product: productName, app: app),
                  deployment.hasDetails
            else { return .failure("Deployment not found or no details to display.") }
            
            let current = state["detailsExpanded"]?.bool ?? false
            state["detailsExpanded"] = .bool(!current)
            
            return .success()
        }

    }

}

func loadDeployment(id: UUID, product: String, app: Application) async -> Deployment? {
    do {
        guard let deployment = try await Deployment.find(id, on: app.db),
              deployment.product == product
        else { return nil }
        return deployment
    } catch {
        app.logger.error("\(MistError.databaseFetchFailed("Deployment id=\(id)", error))")
        return nil
    }
}
