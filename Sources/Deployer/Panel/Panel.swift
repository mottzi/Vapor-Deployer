import Vapor
import Fluent
import Mist

extension Deployer {
    
    func usePanel(config: Configuration, row: RowComponent, configComponent: ConfigComponent) {

        let panel = Panel(config: config, row: row, configComponent: configComponent)
        let router = app.grouped(config.panelRoute.pathComponents).grouped(app.sessions.middleware)
        
        panel.registerAssetRoutes(on: app.grouped(config.panelRoute.pathComponents))
        
        router.get("login")   { try await panel.serveLogin(request: $0) }
        router.post("login")  { try panel.handleLogin(request: $0) }
        router.post("logout") { panel.handleLogout(request: $0) }
        
        let authRouter = router.grouped(panel.authenticator)
        
        authRouter.get()      { try await panel.servePanel(request: $0) }
    }
    
}

struct Panel {
    
    let config: Configuration
    let row: RowComponent
    let configComponent: ConfigComponent
    let panelPath: String
    let loginPath: String
    let authenticator: PanelAuthenticator
    
    init(config: Configuration, row: RowComponent, configComponent: ConfigComponent) {
        
        self.panelPath = config.panelRoute.displayPath
        self.loginPath = panelPath == "/" ? "/login" : panelPath + "/login"
        self.authenticator = PanelAuthenticator(path: loginPath)
        self.config = config
        self.row = row
        self.configComponent = configComponent
    }
    
}

extension Panel {
    
    /// Registers routes that serve deployer static assets (CSS, JS, images) from `Public/deployer/` under the configured panel route prefix.
    func registerAssetRoutes(on router: RoutesBuilder) {
        for asset in ["deployer.css", "mist.js", "morphdom.js", "mottzi.png"] {
            router.get(PathComponent(stringLiteral: asset)) { request async throws -> Response in
                let filePath = request.application.directory.publicDirectory + "deployer/" + asset
                return try await request.fileio.asyncStreamFile(at: filePath)
            }
        }
    }
    
    func serveLogin(request: Request) async throws -> View {
        let hasError = request.query[String.self, at: "error"] != nil
        let loginContext = LoginViewContext(
            error: hasError,
            panelRoute: panelPath,
            repositoryWebPageURL: DeployerVersion.repositoryWebPageURL
        )
        return try await request.view.render("Deployer/DeployerPanelLogin", loginContext)
    }

    func handleLogin(request: Request) throws -> Response {
        
        let userPassword = try request.content.decode(LoginFormData.self).password
        let serverPasswordHash = Deployer.Variables.PANEL_PASSWORD_HASH.value
        guard (try? Bcrypt.verify(userPassword, created: serverPasswordHash)) == true else {
            return request.redirect(to: loginPath + "?error=true")
        }
        
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
        async let configRender = configComponent.renderCurrent(app: request.application)

        let deployerVersion = await DeployerVersion.current()

        let deployer = DeployerContext(
            version: deployerVersion,
            port: String(config.port),
            deployerDirectory: config.deployerDirectory,
            mistSocket: config.socketPath.displayPath,
            panelRoute: config.panelRoute.displayPath,
            repositoryWebPageURL: DeployerVersion.repositoryWebPageURL
        )

        let target = TargetContext(
            name: config.target.name,
            directory: config.target.directory,
            buildMode: config.target.buildMode,
            deployMode: config.target.deploymentMode.rawValue,
            pushEvent: config.target.pusheventPath.displayPath,
            rows: try await rows.contexts,
            isRunning: await isRunning,
            queueIsDeploying: await queueIsDeploying,
            configComponentName: configComponent.name,
            configInitialHTML: await configRender.html ?? ""
        )
        
        return PanelContext(deployer: deployer, target: target)
    }
    
}

extension Panel {
    
    struct PanelContext: Encodable {
        let deployer: DeployerContext
        let target: TargetContext
    }

    struct DeployerContext: Encodable {
        let version: String
        let port: String
        let deployerDirectory: String
        let mistSocket: String
        let panelRoute: String
        let repositoryWebPageURL: String
    }

    struct TargetContext: Encodable {
        let name: String
        let directory: String
        let buildMode: String
        let deployMode: String
        let pushEvent: String
        let rows: [ModelContext]
        let isRunning: Bool
        let queueIsDeploying: Bool
        let configComponentName: String
        let configInitialHTML: String
    }

    struct LoginViewContext: Encodable {
        let error: Bool
        let panelRoute: String
        let repositoryWebPageURL: String
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
