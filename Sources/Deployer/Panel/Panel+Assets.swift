import Vapor

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
    
}
