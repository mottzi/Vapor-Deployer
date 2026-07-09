import Vapor

extension OperationCoordinator {

    /// Finds the newest non-superseded `.queued` row at boot and starts automatic drain.
    func drainOnBoot() async {
        guard config.target.deploymentMode == .automatic else { return }
        guard let seed = try? await bootDrainSeed() else { return }
        await start(deployment: seed, target: config.target, mode: .automaticDeploy)
    }

    /// Returns the newest `.queued` row for this product that has not been superseded, or nil.
    private func bootDrainSeed() async throws -> Deployment? {
        
        let candidate = try await Deployment.query(on: app.db)
            .filter(\.$product, .equal, config.target.name)
            .filter(\.$status, .equal, .queued)
            .sort(\.$startedAt, .descending)
            .first()

        guard let candidate, try await !candidate.isSuperseded(on: app.db) else { return nil }
        return candidate
    }

}
