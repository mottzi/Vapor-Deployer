import Vapor
import Mist

extension OperationCoordinator {

    /// Delegates accepted work to the shared engine, then clears the in-process busy flag.
    func run(mode: OperationMode, startingWith deployment: Deployment, lock: OperationLock) async {

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

    /// Resolves display phase from global locks first, then the server-local operation flag.
    func resolvedPhase() async -> DeployerPhase {
        
        let isUpdating = await app.deployer.updater.isUpdating
        
        return DeployerPhase.resolve(
            updaterIsUpdating: isUpdating,
            operationIsDeploying: isDeploying
        )
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
            try await DeploymentRow.syncAll(for: config.target.name, in: app)
        } catch {
            app.logger.error("Failed to refresh deployment rows after operation completion: \(error.localizedDescription)")
        }
    }

}
