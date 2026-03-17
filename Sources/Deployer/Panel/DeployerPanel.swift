import Vapor
import Fluent
import Mist

extension Deployer {
    
    func usePanel(config: DeployerConfiguration) {

        let panel = DeployerPanel(config: config)
        
        let router = app.grouped(config.panelRoute).grouped(app.sessions.middleware)
        router.get("login")     { try await panel.serveLogin(request: $0) }
        router.post("login")    { try panel.handleLogin(request: $0) }
        router.post("logout")   { panel.handleLogout(request: $0) }
        
        let authRouter = router.grouped(panel.authenticator)
        authRouter.get()        { try await panel.servePanel(request: $0, config: config) }
    }
    
}

struct DeployerPanel {
    
    let panelPath: String
    let loginPath: String
    let authenticator: PanelAuthenticator
    
    init(config: DeployerConfiguration) {
        panelPath = "/" + config.panelRoute.map(\.description).joined(separator: "/")
        loginPath = panelPath + "/login"
        authenticator = PanelAuthenticator(path: loginPath)
    }
    
}
