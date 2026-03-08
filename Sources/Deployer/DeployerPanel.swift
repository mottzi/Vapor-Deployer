import Vapor
import Fluent
import Mist

extension Deployer {
    
    func usePanel(config: DeployerConfiguration) {
        
        // 1. Enable session support for the application
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
                // Manually log the user in; the session authenticator will save this to the cookie
                request.auth.login(AdminUser())
                return request.redirect(to: "/" + config.panelRoute.map(\.description).joined(separator: "/"))
            } else {
                return request.redirect(to: "/login?error=true")
            }
        }
        
        // 4. Create a protected route group
        // Be sure to include the Session Authenticator BEFORE the RedirectMiddleware
        let protected = app.grouped(
            AdminSessionAuthenticator(),
            AdminUser.redirectMiddleware(path: "/login") //
        )
        
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

// 1. A dummy user type for our single admin
struct AdminUser: SessionAuthenticatable {
    var sessionID: String { "admin_user" }
}

// 2. The authenticator that restores the user from the session cookie
struct AdminSessionAuthenticator: AsyncSessionAuthenticator {
    typealias User = AdminUser
    
    func authenticate(sessionID: String, for request: Request) async throws {
        if sessionID == "admin_user" {
            request.auth.login(AdminUser())
        }
    }
}

// 3. The struct to decode your HTML form POST
struct LoginFormData: Content {
    let password: String
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
