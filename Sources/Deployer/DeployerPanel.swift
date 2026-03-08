import Vapor
import Fluent
import Mist

extension Deployer {
    
    func usePanel(config: DeployerConfiguration) {
            
        let panelPath = "/" + config.panelRoute.map(\.description).joined(separator: "/")
        let loginPath = panelPath + "/login"
        
        // 1. Enable sessions globally for the app
        app.middleware.use(app.sessions.middleware)
        
        // 2. Serve the login page
        app.get(config.panelRoute + ["login"]) { request async throws -> View in
            let hasError = request.query[String.self, at: "error"] != nil
            return try await request.view.render("Deployer/Login", ["error": hasError])
        }
        
        // 3. Process the login form
        app.post(config.panelRoute + ["login"]) { request async throws -> Response in
            let formData = try request.content.decode(LoginFormData.self)
            
            if formData.password == Deployer.Variables.PANEL_PASSWORD.value {
                
                // THE FOOLPROOF FIX: Write directly to the session data dictionary!
                request.session.data["admin_auth"] = "true"
                
                return request.redirect(to: panelPath)
            } else {
                return request.redirect(to: loginPath + "?error=true")
            }
        }
        
        // 4. Protect the panel route with our custom middleware
        let protected = app.grouped(PanelSessionMiddleware(loginPath: loginPath))
        
        // 5. Your panel route
        protected.get(config.panelRoute) { request async throws -> View in
            
            let deployer = await config.deployerRowComponent.makeContext(ofAll: request.db)
            let server = await config.serverRowComponent.makeContext(ofAll: request.db)
            let current = try? await Deployment.getCurrent(named: config.serverTarget.productName, on: request.db)
            
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
            
            return try await request.view.render("Deployer/DeploymentPanel", context)
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
    
}

struct LoginFormData: Content {
    let password: String
}

struct PanelSessionMiddleware: AsyncMiddleware, Sendable {
    let loginPath: String
    
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        // Explicitly check the session data dictionary
        if request.session.data["admin_auth"] == "true" {
            return try await next.respond(to: request)
        }
        
        // Not authenticated, redirect to the login page
        return request.redirect(to: loginPath)
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
