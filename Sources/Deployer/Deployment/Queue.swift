import Vapor
import Mist

extension Deployer {
    
    func useQueue(
        config: Configuration,
        queueState: LiveState<QueueState>,
        onStatusChange: @escaping @Sendable (ServiceStatus) async -> Void
    ) {
        queue = Queue(app: app, config: config, queueState: queueState, onStatusChange: onStatusChange)
    }
    
    var queue: Queue {
        get {
            if let queue = app.storage[QueueKey.self] { return queue }
            fatalError("Queue not initialized.")
        }
        nonmutating set {
            app.storage[QueueKey.self] = newValue
        }
    }
    
    struct QueueKey: StorageKey { typealias Value = Queue }
    
}

actor Queue {
        
    var isDeploying: Bool = false
    
    let app: Application
    let config: Configuration
    let queueState: LiveState<QueueState>
    let onStatusChange: @Sendable (ServiceStatus) async -> Void
    
    init(
        app: Application,
        config: Configuration,
        queueState: LiveState<QueueState>,
        onStatusChange: @escaping @Sendable (ServiceStatus) async -> Void
    ) {
        self.app = app
        self.config = config
        self.queueState = queueState
        self.onStatusChange = onStatusChange
    }
    
    func recordPush(event: PushEvent, target: TargetConfiguration) async {
        
        let eventBranch = event.branch.hasPrefix("refs/heads/")
            ? String(event.branch.dropFirst("refs/heads/".count))
            : event.branch

        guard eventBranch == target.branch else { return }
        
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

        deployment.startedAt = .now
        try? await deployment.save(on: app.db)
        
    }
    
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
        await start(deployment: deployment, target: target, mode: .restoreBinary, preserveOutput: true)
    }

    private func start(deployment: Deployment, target: TargetConfiguration, mode: JobMode, preserveOutput: Bool = false) async -> StartResult {

        guard !isDeploying else { return .queueBusy }

        isDeploying = true
        await updateUI()

        deployment.startedAt = .now
        deployment.status = .running
        deployment.finishedAt = nil

        if !preserveOutput {
            deployment.output = nil
        }

        do {
            try await deployment.save(on: app.db)
        } catch {
            isDeploying = false
            await updateUI()

            return .failure("Failed to start deployment: \(error.localizedDescription)")
        }

        Task { await self.run(mode: mode, startingWith: deployment, initialTarget: target) }
        return .started
    }
    
}

extension Queue {

    enum JobMode: Sendable {
        case deploy
        case saveBinary
        case restoreBinary
    }
    
    enum StartResult: Sendable {
        case started
        case queueBusy
        case failure(String)
    }
    
    func updateUI() async {
        let newState = QueueState(isDeploying: isDeploying)
        await queueState.set(newState)
    }

    func run(mode: JobMode, startingWith initialDeployment: Deployment, initialTarget: TargetConfiguration) async {
        switch mode {
        case .deploy:
            await drainQueue(startingWith: initialDeployment, initialTarget: initialTarget)
        case .saveBinary, .restoreBinary:
            await runSingle(deployment: initialDeployment, target: initialTarget, mode: mode)
        }

        isDeploying = false
        await updateUI()
    }

    func runSingle(deployment: Deployment, target: TargetConfiguration, mode: JobMode) async {
        let worker = Worker(
            deployment: deployment,
            target: target,
            app: app,
            onStatusChange: onStatusChange
        )
        let store = BinaryStore(target: target)
        let buildOutput = MistStreamRelay(app: app, deployment: deployment)

        var capturedOutput: String?
        do {
            await buildOutput.start()

            switch mode {
            case .saveBinary:
                try await worker.checkout()
                capturedOutput = try await worker.build(streamingTo: buildOutput)
                await buildOutput.flush()
                try await store.storeBuiltBinary(for: deployment, app: app, manually: true)

                deployment.status = .success
                deployment.finishedAt = .now
                deployment.output = capturedOutput
                try await deployment.save(on: app.db)

            case .restoreBinary:
                try await worker.restore(from: store)
                try await worker.restart()

                deployment.finishedAt = .now
                try await store.syncMetadata(for: deployment, on: app.db)
                try await deployment.setCurrent(on: app.db)
                try await store.evict(on: app.db)

            case .deploy:
                preconditionFailure("runSingle does not execute deploy jobs")
            }

            await buildOutput.close()
        } catch {
            await fail(deployment: deployment, buildOutput: buildOutput, capturedOutput: capturedOutput, error: error)
        }
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
            let buildOutput = MistStreamRelay(app: app, deployment: currentDeployment)
            
            var capturedOutput: String?
            do {
                await buildOutput.start()
                try await worker.checkout()
                capturedOutput = try await worker.build(streamingTo: buildOutput)
                await buildOutput.flush()
                try await worker.move()

                currentDeployment.status = .success
                currentDeployment.finishedAt = .now
                currentDeployment.output = capturedOutput
                try await currentDeployment.save(on: app.db)
                
                guard let nextDeployment = try await findNextDeployment(after: currentDeployment) else {
                    try await worker.restart()
                    let store = BinaryStore(target: currentTarget)
                    try await store.storeLiveBinary(for: currentDeployment, app: app, manually: false)
                    try await currentDeployment.setCurrent(on: app.db)
                    try await store.evict(on: app.db)
                    await buildOutput.close()
                    break
                }

                await buildOutput.close()

                nextDeployment.status = .running
                try? await nextDeployment.save(on: app.db)

                currentTarget = config.target
                currentDeployment = nextDeployment
            } catch {
                await fail(deployment: currentDeployment, buildOutput: buildOutput, capturedOutput: capturedOutput, error: error)
                break
            }
        }
    }

    func fail(
        deployment: Deployment,
        buildOutput: MistStreamRelay,
        capturedOutput: String?,
        error: Swift.Error
    ) async {
        await buildOutput.flush()
        deployment.status = .failed
        deployment.finishedAt = .now

        var finalOutput = ""
        if let capturedOutput {
            finalOutput = capturedOutput + "\n\n"
        }

        if let shellError = error as? Shell.Error {
            finalOutput += shellError.output
        } else {
            finalOutput += error.localizedDescription
        }
        deployment.output = finalOutput.trimmingCharacters(in: .whitespacesAndNewlines)

//        if !app.didShutdown {
            try? await deployment.save(on: app.db)
//        }
        await buildOutput.close()
    }
    
    func findNextDeployment(after deployment: Deployment) async throws -> Deployment? {
        
        guard let currentTime = deployment.startedAt else { return nil }

        let candidate = try await Deployment.query(on: app.db)
            .filter(\.$product, .equal, deployment.product)
            .filter(\.$status, .equal, .canceled)
            .filter(\.$startedAt, .greaterThan, currentTime)
            .sort(\.$startedAt, .descending)
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
