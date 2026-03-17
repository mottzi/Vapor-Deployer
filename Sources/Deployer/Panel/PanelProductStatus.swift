import Vapor
import Fluent
import Mist

public struct PanelProductStatus: Mist.QueryComponent {

    public let productName: String

    public var name: String { "PanelProductStatus-\(productName)" }
    public let models: [any Mist.Model.Type] = [DeployerProductStatus.self]
    public let template: Template = .file(path: "Deployer/PanelProductStatus")
    public let actions: [any Mist.Action]

    public func queryModel(on db: Database) async -> (any Mist.Model)? {
        try? await DeployerProductStatus.query(on: db)
            .filter(\.$productName == productName)
            .first()
    }

    public init(productName: String) {
        self.productName = productName
        self.actions = [RestartAction(productName: productName), StopAction(productName: productName)]
    }

}

extension PanelProductStatus {
    
    struct RestartAction: Mist.Action {

        let name = "restart"
        let productName: String

        func perform(id: UUID?, state: inout MistState, on db: Database) async -> ActionResult {
            do {
                try await DeployerProductStatus.upsert(productName: productName, isRunning: false, on: db)
                try await Supervisor.restart(product: productName)
                try await DeployerProductStatus.upsert(productName: productName, isRunning: true, on: db)
                return .success()
            } catch {
                return .failure(message: error.localizedDescription)
            }
        }

    }

    struct StopAction: Mist.Action {

        let name = "stop"
        let productName: String

        func perform(id: UUID?, state: inout MistState, on db: Database) async -> ActionResult {
            do {
                try await Supervisor.stop(product: productName)
                try await DeployerProductStatus.upsert(productName: productName, isRunning: false, on: db)
                return .success()
            } catch {
                return .failure(message: error.localizedDescription)
            }
        }

    }
    
}
