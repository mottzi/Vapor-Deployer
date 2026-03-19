import Vapor
import Fluent
import Mist

public struct StatusComponent: Mist.PollingComponent {

    public let productName: String

    public var name: String { "StatusComponent-\(productName)" }
    public let interval: Duration = .seconds(3)
    public let template: Template = .file(path: "Deployer/StatusComponent")
    public let actions: [any Mist.Action]

    public init(productName: String) {
        self.productName = productName
        self.actions = [RestartAction(productName: productName), StopAction(productName: productName)]
    }

    public func poll(on db: Database) async -> Context? {
        let isRunning = await DeployerShell.Supervisor.isRunning(product: productName)
        return Context(productName: productName, isRunning: isRunning)
    }

    public struct Context: Encodable, Equatable {
        let productName: String
        let isRunning: Bool
    }

}

extension StatusComponent {

    struct RestartAction: Mist.Action {

        let name = "restart"
        let productName: String

        func perform(id: UUID?, state: inout MistState, on db: Database) async -> ActionResult {
            do {
                try await DeployerShell.Supervisor.restart(product: productName)
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
                try await DeployerShell.Supervisor.stop(product: productName)
                return .success()
            } catch {
                return .failure(message: error.localizedDescription)
            }
        }

    }

}
