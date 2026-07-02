import Vapor

extension OperationCoordinator {

    /// Finds the newest non-superseded `.canceled` row at boot and starts automatic drain.
    func drainOnBoot() async {
        guard config.target.deploymentMode == .automatic else { return }
        guard let seed = try? await bootDrainSeed() else { return }
        _ = await start(deployment: seed, target: config.target, mode: .automaticDeploy)
    }

    /// Returns the newest `.canceled` row for this product that has not been superseded, or nil.
    private func bootDrainSeed() async throws -> Deployment? {
        
        let candidate = try await Deployment.query(on: app.db)
            .filter(\.$product, .equal, config.target.name)
            .filter(\.$status, .equal, .canceled)
            .sort(\.$startedAt, .descending)
            .first()

        guard let candidate, try await !isSuperseded(candidate) else { return nil }
        return candidate
    }

    /// Returns true if a newer successful deployment already ran, making this candidate stale.
    private func isSuperseded(_ deployment: Deployment) async throws -> Bool {

        guard let startedAt = deployment.startedAt else { return false }

        if let currentDeployment = try await Deployment.getCurrent(named: deployment.product, on: app.db),
           let currentStartedAt = currentDeployment.startedAt,
           currentStartedAt >= startedAt {

            return true
        }

        let isSuperseded = try await Deployment.query(on: app.db)
            .filter(\.$product, .equal, deployment.product)
            .filter(\.$startedAt, .greaterThan, startedAt)
            .group(.or) {
                $0
                    .filter(\.$status, .equal, .built)
                    .filter(\.$status, .equal, .running)
            }
            .first() != nil

        return isSuperseded
    }

}
