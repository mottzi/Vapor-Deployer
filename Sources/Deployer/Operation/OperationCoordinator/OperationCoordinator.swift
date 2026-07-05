import Vapor
import Mist

extension Deployer {

    func useOperations(
        config: Configuration,
        deployerPhase: LiveState<DeployerPhase>,
        onStatusChange: @escaping @Sendable (ServiceStatus) async -> Void
    ) {
        operations = OperationCoordinator(app: app, config: config, deployerPhase: deployerPhase, onStatusChange: onStatusChange)
    }

    var operations: OperationCoordinator {
        get {
            if let operations = app.storage[OperationCoordinatorKey.self] { return operations }
            fatalError("OperationCoordinator not initialized.")
        }
        nonmutating set {
            app.storage[OperationCoordinatorKey.self] = newValue
        }
    }

    private struct OperationCoordinatorKey: StorageKey { typealias Value = OperationCoordinator }

}

actor OperationCoordinator {
    
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

extension OperationCoordinator {

    /// Determines which execution path the coordinator takes for a given job.
    enum OperationMode {

        /// Full build-and-deploy pipeline, draining any queued pushes in sequence.
        case deploy

        /// Automatic-mode build-and-deploy pipeline that drains newer queued pushes.
        case automaticDeploy

        /// Build and archive the binary without deploying it live.
        case saveBinary

        /// Swap the live binary from a previously saved archive.
        case restoreBinary

        /// Run `swift test` against the deployment's commit without building or deploying.
        case test

    }

    /// Outcome returned to callers after attempting to start an operation job.
    enum StartResult {
        
        /// Job accepted and running in the background.
        case started
        
        /// Rejected because another job is already in progress.
        case operationBusy
        
        /// Job could not start due to a DB or internal error.
        case failure(String)
        
    }

}

private extension OperationCoordinator {

    /// Treats any cross-process deployer operation as busy when classifying automatic webhook pushes.
    func globalOperationLockHeld() -> Bool {

        let updateLockHeld = UpdateLock.isHeld()
        let operationLockHeld = OperationLock.isHeld()

        return updateLockHeld || operationLockHeld
    }

}

extension OperationCoordinator {
    
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

extension OperationCoordinator {
    
    ///
    func start(deployment: Deployment, target: TargetConfiguration, mode: OperationMode) async -> StartResult {

        guard !isDeploying else { return .operationBusy }
        let isUpdating = await app.deployer.updater.isUpdating
        guard !isUpdating else { return .operationBusy }

        let lock: OperationLock
        
        do {
            if UpdateLock.isHeld() { return .operationBusy }
            lock = try OperationLock.acquire()
        } catch OperationError.anotherOperationInProgress {
            return .operationBusy
        } catch {
            return .failure(error.localizedDescription)
        }

        isDeploying = true
        await broadcastState()
        Task { await run(mode: mode, startingWith: deployment, lock: lock) }
        
        return .started
    }

}
