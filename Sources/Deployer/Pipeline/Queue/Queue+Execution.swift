import Vapor
import Mist

extension Queue {

    /// Delegates accepted work to the shared engine, then clears the in-process busy flag.
    func run(mode: JobMode, startingWith deployment: Deployment, lock: OperationLock) async {

        let engine = OperationEngine(
            app: app,
            config: config,
            onStatusChange: onStatusChange
        )

        let action: OperationEngine.Action = switch mode {
        case .deploy: .deploy
        case .automaticDeploy: .automaticDeploy
        case .saveBinary: .build
        case .restoreBinary: .runSavedBinary
        case .test: .test
        }

        do {
            try await engine.run(action: action, deployment: deployment)
        } catch {
            app.logger.error("Deployment operation failed: \(error.localizedDescription)")
        }

        lock.release()
        await finish()
    }

    /// Broadcasts current operation state to connected live panel clients.
    func broadcastState() async {
        let phase = await resolvedPhase()
        await deployerPhase.set(phase)
    }

    /// Resolves display phase from global locks first, then the server-local queue flag.
    func resolvedPhase() async -> DeployerPhase {
        guard let installDirectory = try? Configuration.getExecutableURL().deletingLastPathComponent() else {
            return isDeploying ? .deploying : .ready
        }

        if UpdateLock.isHeld(installDirectory: installDirectory) {
            return .updating
        }

        if OperationLock.isHeld(installDirectory: installDirectory) || isDeploying {
            return .deploying
        }

        return .ready
    }

    /// Clears the server-local busy bit after a detached operation completes.
    private func finish() async {
        isDeploying = false
        await broadcastState()
        await refreshProductRows()
    }

    /// Re-renders deployment rows after global lock state changes.
    private func refreshProductRows() async {
        do {
            let deployments = try await Deployment.query(on: app.db)
                .filter(\.$product, .equal, config.target.name)
                .all()

            for deployment in deployments {
                guard let id = deployment.id else { continue }
                await app.mist.models.sync(Deployment.self, id: id)
            }
        } catch {
            app.logger.error("Failed to refresh deployment rows after queue completion: \(error.localizedDescription)")
        }
    }

}

extension Queue {

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
