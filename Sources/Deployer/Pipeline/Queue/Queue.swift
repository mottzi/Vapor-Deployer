import Vapor
import Mist

///
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

    ///
    func recordPush(event: PushEvent, target: TargetConfiguration) async {

        let eventBranch = event.branch.hasPrefix("refs/heads/")
            ? String(event.branch.dropFirst("refs/heads/".count))
            : event.branch

        guard eventBranch == target.branch else { return }

        let isUpdating = await app.deployer.updater.isUpdating
        let isOperationLocked = globalOperationLockHeld()
        let status: Deployment.Status = switch target.deploymentMode {
            case .automatic: (isDeploying || isUpdating || isOperationLocked) ? .canceled : .building
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
            let result = await start(deployment: deployment, target: target, mode: .automaticDeploy)
            if case .started = result { return }

            deployment.status = .canceled
            deployment.startedAt = .now
            try? await deployment.save(on: app.db)
            return
        }
        
        deployment.startedAt = .now
        try? await deployment.save(on: app.db)
    }
    
}

private extension Queue {

    /// Treats any cross-process deployer operation as busy when classifying automatic webhook pushes.
    func globalOperationLockHeld() -> Bool {

        let updateLockHeld = UpdateLock.isHeld()
        let operationLockHeld = OperationLock.isHeld()

        return updateLockHeld || operationLockHeld
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
    
    ///
    func start(deployment: Deployment, target: TargetConfiguration, mode: JobMode) async -> StartResult {

        guard !isDeploying else { return .queueBusy }
        let isUpdating = await app.deployer.updater.isUpdating
        guard !isUpdating else { return .queueBusy }

        let lock: OperationLock
        
        do {
            if UpdateLock.isHeld() { return .queueBusy }
            lock = try OperationLock.acquire()
        } catch OperationError.anotherOperationInProgress {
            return .queueBusy
        } catch {
            return .failure(error.localizedDescription)
        }

        isDeploying = true
        await broadcastState()
        Task { await run(mode: mode, startingWith: deployment, lock: lock) }
        
        return .started
    }

}
