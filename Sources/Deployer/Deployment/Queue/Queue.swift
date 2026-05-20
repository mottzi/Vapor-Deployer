import Vapor
import Mist

actor Queue {
    
    var isDeploying: Bool = false
    
    let app: Application
    let config: Configuration
    let deployerPhase: LiveState<DeployerPhase>
    let onStatusChange: @Sendable (ServiceStatus) async -> Void

    init(
        app: Application,
        config: Configuration,
        deployerPhase: LiveState<DeployerPhase>,
        onStatusChange: @escaping @Sendable (ServiceStatus) async -> Void
    ) {
        self.app = app
        self.config = config
        self.deployerPhase = deployerPhase
        self.onStatusChange = onStatusChange
    }

    func recordPush(event: PushEvent, target: TargetConfiguration) async {

        let eventBranch = event.branch.hasPrefix("refs/heads/")
            ? String(event.branch.dropFirst("refs/heads/".count))
            : event.branch

        guard eventBranch == target.branch else { return }

        let isUpdating = await app.deployer.updater.isUpdating
        let status: Deployment.Status = switch target.deploymentMode {
            case .automatic: (isDeploying || isUpdating) ? .canceled : .building
            case .manual: .pushed
        }
        
        let deployment = Deployment(
            product: target.name,
            status: status,
            commitMessage: event.deploymentMessage,
            commitID: event.commitID,
            branch: event.branch
        )
        
        if deployment.status == .building {
            await deploy(deployment: deployment, target: target)
            return
        }
        
        deployment.startedAt = .now
        try? await deployment.save(on: app.db)
    }
    
}

extension Queue {
    
    @discardableResult
    func deploy(deployment: Deployment, target: TargetConfiguration) async -> StartResult {
        await start(deployment: deployment, target: target, mode: .deploy)
    }

    @discardableResult
    func saveBinary(deployment: Deployment, target: TargetConfiguration) async -> StartResult {
        await start(deployment: deployment, target: target, mode: .saveBinary)
    }

    @discardableResult
    func restoreBinary(deployment: Deployment, target: TargetConfiguration) async -> StartResult {
        await start(deployment: deployment, target: target, mode: .restoreBinary)
    }

    @discardableResult
    func test(deployment: Deployment, target: TargetConfiguration) async -> StartResult {
        await start(deployment: deployment, target: target, mode: .test)
    }

}

extension Queue {
    
    private func start(deployment: Deployment, target: TargetConfiguration, mode: JobMode) async -> StartResult {

        guard !isDeploying else { return .queueBusy }
        let isUpdating = await app.deployer.updater.isUpdating
        guard !isUpdating else { return .queueBusy }

        // Cross-process gap closure (ADR 0005): refuse if any deployer update — including one launched
        // from a shell — currently holds the update lock. `Updater.isUpdating` above is now derived
        // from the same source, but we peek directly to defend against a poll-cadence race where a
        // CLI update started milliseconds ago has not yet been observed by the Updater's watcher.
        if let installDirectory = try? Configuration.getExecutableURL().deletingLastPathComponent(),
           UpdateLock.isHeld(installDirectory: installDirectory) {
            return .queueBusy
        }

        isDeploying = true
        await broadcastState()

        // Manual test is an audit — runTest snapshots/restores the row's lifecycle state itself.
        // For every other mode, start() owns the .testing/.building/.restoring flip + save.
        if mode != .test {
            deployment.startedAt = .now
            deployment.status = switch mode {
                case .restoreBinary: .restoring
                default: .building
            }
            deployment.finishedAt = nil

            // .restoreBinary preserves the prior build transcript so the user can compare.
            if mode != .restoreBinary { deployment.output = nil }

            do {
                try await deployment.save(on: app.db)
            } catch {
                isDeploying = false
                await broadcastState()
                return .failure("Failed to start deployment: \(error.localizedDescription)")
            }
        }

        Task { await run(mode: mode, startingWith: deployment, on: target) }
        return .started
    }

}
