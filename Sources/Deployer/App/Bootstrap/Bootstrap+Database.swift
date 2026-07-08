import Foundation
import Fluent

extension Deployer {
    
    func configureDatabase(config: Configuration) async throws {
        try createDatabaseDirectory(for: config.dbFile)
        app.databases.use(.sqlite(.file(config.dbFile)), as: .sqlite)
        app.databases.middleware.use(BinaryStore.CleanupMiddleware(target: config.target))
        app.sessions.use(.fluent)
        app.migrations.add(Deployment.migrations + Operation.migrations + OperationEvent.migrations + [SessionRecord.migration])
        try await app.autoMigrate()
        await seedFirstDeployment(config: config)
    }
    
    func configureHeadlessDatabase(config: Configuration) async throws {
        try createDatabaseDirectory(for: config.dbFile)
        app.databases.use(.sqlite(.file(config.dbFile)), as: .sqlite)
        app.databases.middleware.use(BinaryStore.CleanupMiddleware(target: config.target))
        app.migrations.add(Deployment.migrations + Operation.migrations + OperationEvent.migrations)
        try await app.autoMigrate()
        await seedFirstDeployment(config: config)
    }
    
}

extension Deployer {

    private func createDatabaseDirectory(for dbFile: String) throws {

        let dbDirectoryPath = URL(fileURLWithPath: dbFile).deletingLastPathComponent().path
        let workingDirectoryPath = app.directory.workingDirectory

        guard !Host.Path.isSamePath(dbDirectoryPath, workingDirectoryPath) else { return }
        try FileManager.default.createDirectory(atPath: Host.Path.standardizedPath(dbDirectoryPath), withIntermediateDirectories: true)
    }

    private func seedFirstDeployment(config: Configuration) async {

        do {
            let existingDeploymentCount = try await Deployment.query(on: app.db)
                .filter(\.$product, .equal, config.target.name)
                .count()

            guard existingDeploymentCount == 0 else { return }

            let checkout = try await Shell.getCurrentCheckout(in: config.target.directory)

            let deployment = Deployment(
                product: config.target.name,
                status: .running,
                commitMessage: checkout.commitMessage,
                commitID: checkout.commitID,
                branch: checkout.branch
            )

            deployment.isLive = true
            deployment.createdAt = checkout.committedAt
            deployment.startedAt = checkout.committedAt
            deployment.finishedAt = checkout.committedAt
            try await deployment.save(on: app.db)
            try await BinaryStore(target: config.target).archiveLiveBinary(for: deployment, app: app, manually: false)

        } catch {
            app.logger.warning("Error when seeding initial deployment for '\(config.target.name)': \(error.localizedDescription)")
        }
    }

}
