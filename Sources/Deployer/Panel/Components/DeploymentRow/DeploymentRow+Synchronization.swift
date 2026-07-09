import Vapor
import Fluent
import Mist

extension DeploymentRow {

    /// Synchronizes every deployment row for a product with Mist's live model registry.
    static func syncAll(for product: String, in app: Application) async throws {
        let deployments = try await Deployment.query(on: app.db)
            .filter(\.$product, .equal, product)
            .all()

        for deployment in deployments {
            guard let id = deployment.id else { continue }
            await app.mist.models.sync(Deployment.self, id: id)
        }
    }

}
