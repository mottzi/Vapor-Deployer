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
    
    static func loadDeployment(id: UUID, product: String, app: Application) async -> Deployment? {
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
    
}


