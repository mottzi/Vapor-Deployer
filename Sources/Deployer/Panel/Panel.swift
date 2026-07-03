import Vapor
import Fluent
import Mist

extension Deployer {
    
    func usePanel(
        config: Configuration,
        row: DeploymentRow,
        targetConfig: TargetConfig,
        deployerConfig: DeployerConfig,
        deployerStatus: DeployerStatus
    ) {
        
        let panel = Panel(
            config: config,
            row: row,
            targetConfig: targetConfig,
            deployerConfig: deployerConfig,
            deployerStatus: deployerStatus
        )
        
        let router = app.grouped(config.panelRoute.pathComponents).grouped(app.sessions.middleware)
        
        panel.registerAssetRoutes(on: app.grouped(config.panelRoute.pathComponents))
        
        router.get("login")   { try await panel.serveLogin(request: $0) }
        router.post("login")  { try panel.handleLogin(request: $0) }
        router.post("logout") { panel.handleLogout(request: $0) }
        
        let authRouter = router.grouped(panel.authenticator)

        authRouter.get()             { try await panel.servePanel(request: $0) }
        authRouter.get("settings")   { try await panel.serveSettings(request: $0) }
        authRouter.post("settings")  { try await panel.handleSettingsSave(request: $0) }
    }
    
}

struct Panel {

    let config: Configuration
    let row: DeploymentRow
    let targetConfig: TargetConfig
    let deployerConfig: DeployerConfig
    let deployerStatus: DeployerStatus
    let panelPath: String
    let loginPath: String
    let authenticator: PanelAuthenticator

    init(
        config: Configuration,
        row: DeploymentRow,
        targetConfig: TargetConfig,
        deployerConfig: DeployerConfig,
        deployerStatus: DeployerStatus
    ) {
        self.panelPath = config.panelRoute.displayPath
        self.loginPath = panelPath == "/" ? "/login" : panelPath + "/login"
        self.authenticator = PanelAuthenticator(path: loginPath)
        self.config = config
        self.row = row
        self.targetConfig = targetConfig
        self.deployerConfig = deployerConfig
        self.deployerStatus = deployerStatus
    }

}

extension Panel {
    
    /// Registers routes that serve deployer static assets (CSS, JS, images) from `Public/deployer/` under the configured panel route prefix.
    func registerAssetRoutes(on router: RoutesBuilder) {
        for asset in ["deployer.css", "mist.js", "morphdom.js", "mottzi.png", "deployer.png", "deployer.ico"] {
            router.get(PathComponent(stringLiteral: asset)) { request async throws -> Response in
                let filePath = request.application.directory.publicDirectory + "deployer/" + asset
                return try await request.fileio.asyncStreamFile(at: filePath)
            }
        }

        router.get("styles", ":filename") { request async throws -> Response in
            guard let filename = request.parameters.get("filename"),
                  filename.hasSuffix(".css"),
                  !filename.contains("/") else { throw Abort(.notFound) }
            let filePath = request.application.directory.publicDirectory + "deployer/styles/" + filename
            return try await request.fileio.asyncStreamFile(at: filePath)
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

        try await DeploymentBinaryStore(target: config.target).syncMetadata(product: config.target.name, on: request.db)

        async let rows = row.makeContext(ofAll: request.db)
        async let isRunning = request.application.deployer.serviceManager.isRunning(product: config.target.name)
        async let isDeploying = request.application.deployer.operations.isDeploying
        async let isUpdating = request.application.deployer.updater.isUpdating
        async let targetInfoRender = targetConfig.renderCurrent(app: request.application)
        async let deployerInfoRender = deployerConfig.renderCurrent(app: request.application)

        let resolvedState = await DeployerPhase.resolve(
            updaterIsUpdating: isUpdating,
            operationIsDeploying: isDeploying
        )
        await deployerStatus.state.set(resolvedState)
        async let deployerStateRender = deployerStatus.renderCurrent(app: request.application)

        let deployer = DeployerContext(
            panelRoute: config.panelRoute.displayPath,
            repositoryWebPageURL: DeployerVersion.repositoryWebPageURL,
            infoComponentName: deployerConfig.name,
            infoInitialHTML: await deployerInfoRender.html ?? "",
            stateComponentName: deployerStatus.name,
            stateInitialHTML: await deployerStateRender.html ?? "",
            state: resolvedState.rawValue
        )

        let target = TargetContext(
            name: config.target.name,
            repositoryURL: config.target.repositoryURL,
            directory: config.target.directory,
            buildMode: config.target.buildMode,
            deployMode: config.target.deploymentMode.rawValue,
            pushEvent: config.target.pusheventPath.displayPath,
            rows: try await rows.contexts,
            isRunning: await isRunning,
            targetConfigName: targetConfig.name,
            targetInfoInitialHTML: await targetInfoRender.html ?? ""
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
        let panelRoute: String
        let repositoryWebPageURL: String
        let infoComponentName: String
        let infoInitialHTML: String
        let stateComponentName: String
        let stateInitialHTML: String
        let state: String
    }

    struct TargetContext: Encodable {
        let name: String
        let repositoryURL: String?
        let directory: String
        let buildMode: String
        let deployMode: String
        let pushEvent: String
        let rows: [ModelContext]
        let isRunning: Bool
        let targetConfigName: String
        let targetInfoInitialHTML: String
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
