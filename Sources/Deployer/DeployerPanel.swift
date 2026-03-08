import Vapor
import Fluent
import Mist

extension Deployer {
    
    func usePanel(config: DeployerConfiguration) {

        let router = app.grouped(config.panelRoute).grouped(app.sessions.middleware)
        let panelPath = "/" + config.panelRoute.map(\.description).joined(separator: "/")
        let loginPath = panelPath + "/login"
        let authMiddleware = PanelAuthenticator(path: loginPath)
        let authRouter = router.grouped(authMiddleware)
        
        router.get("login") { try await serveLogin(request: $0) }
        router.post("login") { try handleLogin(request: $0, panelPath: panelPath, loginPath: loginPath ) }
        router.post("logout") { handleLogout(request: $0, loginPath: loginPath) }
        authRouter.get { try await servePanel(request: $0, config: config) }
    }
    
}
    
private func serveLogin(request: Request) async throws -> View {
    let hasError = request.query[String.self, at: "error"] != nil
    return try await request.view.render("Deployer/DeploymentLogin", ["error": hasError])
}

private func handleLogin(request: Request, panelPath: String, loginPath: String) throws -> Response {
    
    let userPassword = try request.content.decode(LoginFormData.self).password
    let serverPaddword = Deployer.Variables.PANEL_PASSWORD.value
    guard userPassword == serverPaddword else { return request.redirect(to: loginPath + "?error=true") }
    
    request.session.data["admin_auth"] = "true"
    
    return request.redirect(to: panelPath)
}

private func handleLogout(request: Request, loginPath: String) -> Response {
    request.session.destroy()
    return request.redirect(to: loginPath)
}

private func servePanel(request: Request, config: DeployerConfiguration) async throws -> View {
    
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
    
    let context = PanelContext(
        tables: tables,
        component: component
    )
    
    return try await request.view.render("Deployer/DeploymentPanel", context)
}
     
struct PanelContext: Encodable {
    let tables: [TableContext]
    let component: ModelContainer?
}

struct TableContext: Encodable {
    let title: String
    let productName: String
    let rows: [ModelContainer]
}

struct LoginFormData: Content {
    let password: String
}

struct PanelAuthenticator: AsyncMiddleware {
    
    let path: String
    
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        
        let sessionField = request.session.data["admin_auth"]
        guard sessionField == "true" else { return request.redirect(to: path) }
        return try await next.respond(to: request)
    }
    
}
