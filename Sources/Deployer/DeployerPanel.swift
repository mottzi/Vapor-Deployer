import Vapor
import Fluent
import Mist

extension Deployer {
    
    func usePanel(config: DeployerConfiguration) {

        let panelPath = "/" + config.panelRoute.map(\.description).joined(separator: "/")
        let loginPath = panelPath + "/login"

        let panel = app.grouped(config.panelRoute).grouped(app.sessions.middleware)

        panel.post("logout") { req async throws -> Response in
            
            req.session.destroy()
            return req.redirect(to: loginPath)
        }
        
        panel.get("login") { req async throws -> View in
            
            let hasError = req.query[String.self, at: "error"] != nil
            return try await req.view.render("Deployer/DeploymentLogin", ["error": hasError])
        }

        panel.post("login") { req async throws -> Response in
            
            let form = try req.content.decode(LoginFormData.self)
            let expected = Deployer.Variables.PANEL_PASSWORD.value
            guard form.password == expected else { return req.redirect(to: loginPath + "?error=true") }

            req.session.data["admin_auth"] = "true"
            return req.redirect(to: panelPath)
        }

        let protected = panel.grouped(PanelSessionMiddleware(loginPath: loginPath))

        protected.get { req async throws -> View in

            let deployer = await config.deployerRowComponent.makeContext(ofAll: req.db)
            let server = await config.serverRowComponent.makeContext(ofAll: req.db)
            let current = try? await Deployment.getCurrent(named: config.serverTarget.productName, on: req.db)

            let tables = [
                TableContext(
                    title: "Deployer",
                    productName: config.deployerTarget.productName,
                    rows: deployer.components
                ),
                TableContext(
                    title: "Server",
                    productName: config.serverTarget.productName,
                    rows: server.components
                )
            ]

            let component = current.map {
                var container = ModelContainer()
                container.add($0, for: "deployment")
                return container
            }

            let context = DeploymentPanelContext(
                tables: tables,
                component: component
            )

            return try await req.view.render("Deployer/DeploymentPanel", context)
        }
    }
    
}

struct TableContext: Encodable {
    let title: String
    let productName: String
    let rows: [ModelContainer]
}

struct DeploymentPanelContext: Encodable {
    let tables: [TableContext]
    let component: ModelContainer?
}

struct LoginFormData: Content {
    let password: String
}

struct PanelSessionMiddleware: AsyncMiddleware {
    
    let loginPath: String
    
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        
        let sessionField = request.session.data["admin_auth"]
        guard sessionField == "true" else { return request.redirect(to: loginPath) }
        return try await next.respond(to: request)
    }
    
}

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

public struct DeployerPanelStatus: QueryComponent {
    
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
