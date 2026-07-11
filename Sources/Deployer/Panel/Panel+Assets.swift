import Mist
import Vapor

extension Panel {
    
    /// Registers Mist's embedded browser runtime and Deployer-owned static assets under the configured panel route prefix.
    func registerAssetRoutes(on router: RoutesBuilder) {
        
        MistAssetRoutes.register(on: router)

        for asset in ["deployer.css", "mottzi.png", "deployer.png", "deployer.ico"] {
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
