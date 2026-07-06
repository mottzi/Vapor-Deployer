import Vapor
import Fluent

extension BinaryStore {

    /// Scans and synchronizes metadata for all deployments of a given product to recover from out-of-band file modifications.
    func syncMetadata(product: String, on database: Database) async throws {
        let deployments = try await Deployment.query(on: database)
            .filter(\.$product, .equal, product)
            .all()

        for deployment in deployments {
            try await syncMetadata(for: deployment, on: database)
        }
    }

    /// Updates the deployment record's database metadata to align with the actual binary state on the filesystem.
    func syncMetadata(for deployment: Deployment, on database: Database) async throws {
        let size = try binarySizeMB(for: deployment)
        let shouldClearManualSave = size == nil && deployment.isManuallySaved
        guard deployment.binarySizeMB != size || shouldClearManualSave else { return }

        deployment.binarySizeMB = size
        if size == nil {
            deployment.isManuallySaved = false
        }
        try await deployment.save(on: database)
    }

    /// Updates the deployment's storage metadata in the database and registers its manual preservation flag.
    func markStored(_ deployment: Deployment, sizeMB: Int, manually: Bool, on database: Database) async throws {
        deployment.binarySizeMB = sizeMB
        deployment.isManuallySaved = deployment.isManuallySaved || manually
        try await deployment.save(on: database)
    }

}
