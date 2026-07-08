import Vapor

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

        authRouter.get()                   { try await panel.servePanel(request: $0) }
        authRouter.get("logs", "app")      { try await panel.serveTargetAppLogs(request: $0) }
        authRouter.get("logs", "deployer") { try await panel.serveDeployerLogs(request: $0) }
        authRouter.get("settings")         { try await panel.serveSettings(request: $0) }
        authRouter.post("settings")        { try await panel.handleSettingsSave(request: $0) }
    }
    
}
