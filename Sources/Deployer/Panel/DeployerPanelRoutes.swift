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
        
        let deployerRows = await config.deployerRowComponent.makeContext(ofAll: request.db)
        let serverRows = await config.serverRowComponent.makeContext(ofAll: request.db)
        let current = try? await Deployment.getCurrent(named: config.serverTarget.productName, on: request.db)

        let serverStatus = try? await DeployerProductStatus.query(on: request.db)
            .filter(\.$productName == config.serverTarget.productName)
            .first()
        
        let deployerStatus = try? await DeployerProductStatus.query(on: request.db)
            .filter(\.$productName == config.deployerTarget.productName)
            .first()

        let serverStatusContainer: ModelContainer? = serverStatus.map {
            var c = ModelContainer(); c.add($0, for: "deployerproductstatus"); return c
        }
        
        let deployerStatusContainer: ModelContainer? = deployerStatus.map {
            var c = ModelContainer(); c.add($0, for: "deployerproductstatus"); return c
        }

        let tables = [
            TableContext(
                title: "Deployer",
                productName: config.deployerTarget.productName,
                rows: deployerRows.components,
                productStatus: deployerStatusContainer
            ),
            TableContext(
                title: "Server",
                productName: config.serverTarget.productName,
                rows: serverRows.components,
                productStatus: serverStatusContainer
            )
        ]
        
        let component = current.map {
            var container = ModelContainer()
            container.add($0, for: "deployment")
            return container
        }
        
        let context = PanelContext(tables: tables, component: component)
        
        return try await request.view.render("Deployer/DeployerPanel", context)
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
        let productStatus: ModelContainer?
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
