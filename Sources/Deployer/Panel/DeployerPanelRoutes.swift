import Vapor
import Fluent
import Mist

extension DeployerPanel {
    
    func serveLogin(request: Request) async throws -> View {
        let hasError = request.query[String.self, at: "error"] != nil
        return try await request.view.render("Deployer/DeployerPanelLogin", ["error": hasError])
    }

    func handleLogin(request: Request) throws -> Response {
        let userPassword   = try request.content.decode(LoginFormData.self).password
        let serverPassword = Deployer.Variables.PANEL_PASSWORD.value
        guard userPassword == serverPassword else { return request.redirect(to: loginPath + "?error=true") }
        
        request.session.data["admin_auth"] = "true"
        return request.redirect(to: panelPath)
    }

    func handleLogout(request: Request) -> Response {
        request.session.destroy()
        return request.redirect(to: loginPath)
    }
    
    func servePanel(request: Request, config: DeployerConfiguration) async throws -> View {

        async let deployerRows    = config.deployerRowComponent.makeContext(ofAll: request.db)
        async let serverRows      = config.serverRowComponent.makeContext(ofAll: request.db)
        async let current         = Deployment.getCurrent(named: config.serverTarget.productName, on: request.db)
        async let serverRunning   = Supervisor.isRunning(product: config.serverTarget.productName)
        async let deployerRunning = Supervisor.isRunning(product: config.deployerTarget.productName)

        let tables = [
            TableContext(
                title: "Deployer",
                productName: config.deployerTarget.productName,
                rows: await deployerRows.components,
                isRunning: await deployerRunning
            ),
            TableContext(
                title: "Server",
                productName: config.serverTarget.productName,
                rows: await serverRows.components,
                isRunning: await serverRunning
            )
        ]

        let component = try? await current.map {
            var container = ModelContainer()
            container.add($0, for: "deployment")
            return container
        }

        return try await request.view.render("Deployer/DeployerPanel", PanelContext(tables: tables, component: component))
    }
    
}

extension DeployerPanel {
    
    struct PanelContext: Encodable {
        let tables: [TableContext]
        let component: ModelContainer?
    }

    struct TableContext: Encodable {
        let title: String
        let productName: String
        let rows: [ModelContainer]
        let isRunning: Bool
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
    
}
