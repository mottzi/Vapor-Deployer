import Vapor
import Mist

typealias StatusHandler = @Sendable (ServiceStatus) async -> Void

extension Deployer {
    
    func useQueue(
        config: Configuration,
        queueState: LiveState<QueueState>,
        onStatusChange: @escaping StatusHandler
    ) {
        queue = Queue(app: app, config: config, queueState: queueState, onStatusChange: onStatusChange)
    }
    
    var queue: Queue {
        get {
            if let queue = app.storage[DeployerQueueKey.self] { return queue }
            fatalError("Queue not initialized.")
        }
        nonmutating set {
            app.storage[DeployerQueueKey.self] = newValue
        }
    }
    
    private struct DeployerQueueKey: StorageKey { typealias Value = Queue }
    
}

actor Queue {
        
    var isDeploying: Bool = false
    
    let app: Application
    let config: Configuration
    let queueState: LiveState<QueueState>
    let onStatusChange: StatusHandler
    
    init(
        app: Application,
        config: Configuration,
        queueState: LiveState<QueueState>,
        onStatusChange: @escaping StatusHandler
    ) {
        self.app = app
        self.config = config
        self.queueState = queueState
        self.onStatusChange = onStatusChange
    }
    
    func recordPush(event: PushEvent, target: TargetConfiguration) async {
        
        let status: Deployment.Status = switch target.deploymentMode {
            case .automatic: isDeploying ? .canceled : .running
            case .manual: .pushed
        }
        
        let deployment = Deployment(
            product: target.name,
            status: status,
            commitMessage: event.deploymentMessage,
            commitID: event.commitID,
            branch: event.branch
        )
                
        if deployment.status == .running {
            await deploy(deployment: deployment, target: target)
            return
        }
        
        try? await deployment.save(on: app.db)
        
    }
    
    @discardableResult
    func deploy(deployment: Deployment, target: TargetConfiguration) async -> StartResult {
        
        guard !isDeploying else { return .queueBusy }
        
        isDeploying = true
        await updateUI()
        
        deployment.startedAt = .now
        deployment.status = .running
        deployment.finishedAt = nil
        deployment.errorMessage = nil
        
        do {
            try await deployment.save(on: app.db)
        } catch {
            isDeploying = false
            await updateUI()
            
            return .failure("Failed to start deployment: \(error.localizedDescription)")
        }
        
        Task { await self.drainQueue(startingWith: deployment, initialTarget: target) }
        return .started
    }
    
}

extension Queue {
    
    enum StartResult: Sendable {
        case started
        case queueBusy
        case failure(String)
    }
    
    func updateUI() async {
        let newState = QueueState(isDeploying: isDeploying)
        await queueState.set(newState)
    }
    
    func drainQueue(startingWith initialDeployment: Deployment, initialTarget: TargetConfiguration) async {
        
        var currentDeployment = initialDeployment
        var currentTarget = initialTarget
        
        while true {
            let worker = Worker(
                deployment: currentDeployment,
                target: currentTarget,
                app: app,
                onStatusChange: onStatusChange
            )
            
            do {
                try await worker.checkout()
                try await worker.build()
                try await worker.move()

                currentDeployment.status = .success
                currentDeployment.finishedAt = .now
                try await currentDeployment.save(on: app.db)
                
                guard let nextDeployment = try await findNextDeployment(after: currentDeployment) else {
                    try await currentDeployment.setCurrent(on: app.db)
                    try await worker.restart()
                    break
                }

                nextDeployment.status = .running
                try? await nextDeployment.save(on: app.db)

                currentTarget = config.target
                currentDeployment = nextDeployment
            } catch {
                currentDeployment.status = .failed
                currentDeployment.finishedAt = .now
                currentDeployment.errorMessage = error.localizedDescription

                guard !app.didShutdown else { break }
                try? await currentDeployment.save(on: app.db)
                break
            }
        }
        
        isDeploying = false
        await updateUI()
    }
    
    func findNextDeployment(after deployment: Deployment) async throws -> Deployment? {
        
        guard let currentTime = deployment.startedAt else { return nil }

        let candidate = try await Deployment.query(on: app.db)
            .filter(\.$product, .equal, deployment.product)
            .filter(\.$status, .equal, .canceled)
            .filter(\.$startedAt, .greaterThan, currentTime)
            .sort(\.$startedAt, .descending)   // newest wins
            .first()

        guard let candidate, try await !isSuperseded(candidate) else { return nil }
        return candidate
    }

    
    func isSuperseded(_ deployment: Deployment) async throws -> Bool {
        
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
                    .filter(\.$status, .equal, .success)
                    .filter(\.$status, .equal, .deployed)
            }
            .first() != nil

        return isSuperseded
    }
}
