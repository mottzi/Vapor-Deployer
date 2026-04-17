import Vapor
import Fluent
import Mist

extension Deployer {
    
    func usePanel(
        config: DeployerConfiguration,
        row: RowComponent,
        configPopover: ConfigComponent
    ) {

        let panel = DeployerPanel(
            config: config,
            row: row,
            configPopover: configPopover
        )
        
        let router = app.grouped(config.panelRoute.pathComponents).grouped(app.sessions.middleware)
        router.get("login")     { try await panel.serveLogin(request: $0) }
        router.post("login")    { try panel.handleLogin(request: $0) }
        router.post("logout")   { panel.handleLogout(request: $0) }
        
        let authRouter = router.grouped(panel.authenticator)
        authRouter.get()        { try await panel.servePanel(request: $0) }
    }
    
}

struct DeployerPanel {
    
    let config: DeployerConfiguration
    let row: RowComponent
    let configPopover: ConfigComponent
    let panelPath: String
    let loginPath: String
    let authenticator: PanelAuthenticator
    
    init(
        config: DeployerConfiguration,
        row: RowComponent,
        configPopover: ConfigComponent
    ) {
        let joinedPanelPath = config.panelRoute.pathComponents.map(\.description).joined(separator: "/")
        self.panelPath = joinedPanelPath.isEmpty ? "/" : "/" + joinedPanelPath
        self.loginPath = panelPath == "/" ? "/login" : panelPath + "/login"
        self.authenticator = PanelAuthenticator(path: loginPath)
        self.config = config
        self.row = row
        self.configPopover = configPopover
    }
    
}

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
    
    func servePanel(request: Request) async throws -> View {
        let context = try await makePanelContext(request: request)
        return try await request.view.render("Deployer/DeployerPanel", context)
    }

    func makePanelContext(request: Request) async throws -> PanelContext {
        async let rows = row.makeContext(ofAll: request.db)
        async let isRunning = request.application.deployer.serviceManager.isRunning(product: config.target.name)
        async let queueIsDeploying = request.application.deployer.queue.isDeploying
        async let configPopoverRender = configPopover.renderCurrent(app: request.application)

        let tables = [
            TableContext(
                productName: config.target.name,
                rows: try await rows.contexts,
                isRunning: await isRunning,
                showsQueueState: true,
                queueIsDeploying: await queueIsDeploying,
                configPopover: ConfigPopoverContext(
                    componentName: configPopover.name,
                    initialHTML: await configPopoverRender.html ?? ""
                )
            )
        ]
        
        return PanelContext(tables: tables)
    }
    
}

extension DeployerPanel {
    
    struct PanelContext: Encodable {
        let tables: [TableContext]
    }

    struct TableContext: Encodable {
        let productName: String
        let rows: [ModelContext]
        let isRunning: Bool
        let showsQueueState: Bool
        let queueIsDeploying: Bool
        let configPopover: ConfigPopoverContext
    }

    struct ConfigPopoverContext: Encodable {
        let componentName: String
        let initialHTML: String
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
