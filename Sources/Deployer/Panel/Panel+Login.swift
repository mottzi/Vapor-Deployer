import Vapor

extension Panel {
    
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
            request.logger.info("Panel login failed from \(request.remoteAddress?.description ?? "unknown IP")")
            return request.redirect(to: loginPath + "?error=true")
        }
        
        request.logger.info("Panel login successful from \(request.remoteAddress?.description ?? "unknown IP")")
        request.session.data["admin_auth"] = "true"
        return request.redirect(to: panelPath)
    }

    func handleLogout(request: Request) -> Response {
        request.session.destroy()
        return request.redirect(to: loginPath)
    }
    
}

extension Panel {

    struct LoginViewContext: Encodable {
        let error: Bool
        let panelRoute: String
        let repositoryWebPageURL: String
    }

    struct LoginFormData: Content {
        let password: String
    }

    struct Authenticator: AsyncMiddleware {
        
        let path: String
        
        func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
            let sessionField = request.session.data["admin_auth"]
            guard sessionField == "true" else { return request.redirect(to: path) }
            return try await next.respond(to: request)
        }
        
    }
    
}
