import Vapor
import Mist

actor Queue {
    
    var isDeploying: Bool = false
    
    let app: Application
    let config: Configuration
    let deployerState: LiveState<DeployerState>
    let onStatusChange: @Sendable (ServiceStatus) async -> Void

    init(
        app: Application,
        config: Configuration,
        deployerState: LiveState<DeployerState>,
        onStatusChange: @escaping @Sendable (ServiceStatus) async -> Void
    ) {
        self.app = app
        self.config = config
        self.deployerState = deployerState
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

}

extension Queue {
    
    private func start(deployment: Deployment, target: TargetConfiguration, mode: JobMode) async -> StartResult {

        guard !isDeploying else { return .queueBusy }
        let isUpdating = await app.deployer.updater.isUpdating
        guard !isUpdating else { return .queueBusy }

        isDeploying = true
        await broadcastState()

        deployment.startedAt = .now
        deployment.status = mode == .restoreBinary ? .restoring : .building
        deployment.finishedAt = nil

        if mode != .restoreBinary {
            deployment.output = nil
        }

        do {
            try await deployment.save(on: app.db)
        } catch {
            isDeploying = false
            await broadcastState()
            return .failure("Failed to start deployment: \(error.localizedDescription)")
        }

        Task { await run(mode: mode, startingWith: deployment, on: target) }
        return .started
    }

}
