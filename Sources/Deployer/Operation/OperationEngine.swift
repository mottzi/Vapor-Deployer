import Vapor
import Fluent

/// Shared executor for mutating deployment operations across the panel, queue, and CLI.
struct OperationEngine: Sendable {

    let app: Application
    let config: Configuration
    let origin: Operation.Origin
    let onStatusChange: @Sendable (ServiceStatus) async -> Void

    init(
        app: Application,
        config: Configuration,
        origin: Operation.Origin = .server,
        onStatusChange: @escaping @Sendable (ServiceStatus) async -> Void = { _ in }
    ) {
        self.app = app
        self.config = config
        self.origin = origin
        self.onStatusChange = onStatusChange
    }

}

extension OperationEngine {

    /// The specific user-initiated deployment, compilation, or target cleanup command.
    enum Action: Sendable {
        
        case deploy
        case automaticDeploy
        case build
        case runSavedBinary
        case test
        case delete
        case removeBinary

        var kind: Operation.Kind {
            switch self {
                case .deploy, .automaticDeploy: .deploy
                case .build: .build
                case .runSavedBinary: .run
                case .test: .test
                case .delete: .delete
                case .removeBinary: .removeBinary
            }
        }
        
    }

    /// Rules determining whether target-specific test suites must be executed during operation pipelines.
    enum TestPolicy: Sendable {
        case configured
        case forceEnabled
        case forceDisabled
    }

    /// Configuration settings tailoring test execution behavior and output routing for an engine run.
    struct Options: Sendable {
        var testPolicy: TestPolicy = .configured
        var consoleSink: OperationEventConsoleOutputSink?
    }

}

extension OperationEngine {

    /// Runs one operation while the caller retains the cross-process operation lock.
    func run(action: Action, deployment: Deployment, options: Options = Options()) async throws {

        let operation = Operation(kind: action.kind, origin: origin, product: config.target.name, deploymentID: deployment.id)
        try await operation.save(on: app.db)

        let eventLog = try await OperationEventLog(app: app, operation: operation)
        
        do {
            switch action {
                case .deploy: try await runPromote(deployment: deployment, options: options, eventLog: eventLog)
                case .automaticDeploy: try await runAutomaticQueue(startingWith: deployment, options: options, eventLog: eventLog)
                case .build: try await runBuild(deployment: deployment, options: options, eventLog: eventLog)
                case .runSavedBinary: try await runSavedBinary(deployment: deployment, options: options, eventLog: eventLog)
                case .test: try await runTest(deployment: deployment, options: options, eventLog: eventLog)
                case .delete: try await runDelete(deployment: deployment, eventLog: eventLog)
                case .removeBinary: try await runRemoveBinary(deployment: deployment, eventLog: eventLog)
            }
            await eventLog.finish(.completed, deploymentID: deployment.id)
            await cleanupServerOperation(operation)
        } catch {
            await eventLog.finish(.failed, deploymentID: deployment.id)
            await cleanupServerOperation(operation)
            throw error
        }
    }

}

private extension OperationEngine {

    /// Promotes exactly the selected deployment without draining newer queued pushes.
    func runPromote(deployment: Deployment, options: Options, eventLog: OperationEventLog) async throws {

        if deployment.isLive { return }

        let store = BinaryStore(target: config.target)
        let hasSavedBinary = deployment.hasSavedBinary || store.hasBinary(for: deployment)

        if hasSavedBinary {
            guard options.testPolicy != .forceEnabled else { throw OperationError.testingSavedBinaryUnsupported }
            try await runSavedBinary(deployment: deployment, options: options, eventLog: eventLog)
            return
        }

        try await preparePipelineRow(deployment, status: .building, clearOutput: true, eventLog: eventLog)

        let output = makeOutput(deployment: deployment, eventLog: eventLog, options: options)
        let worker = makeWorker(deployment: deployment, output: output, eventLog: eventLog)

        do {
            await output.start()
            try await worker.checkout()
            try await runInlineTestIfNeeded(deployment: deployment, worker: worker, eventLog: eventLog, policy: options.testPolicy)
            try await worker.build()
            try await worker.move()
            try await worker.restart()
            try await worker.deploy(to: store)
            await output.flush()

            deployment.finishedAt = .now
            deployment.output = await output.transcript
            await output.close()

            try await deployment.setCurrent(on: app.db)
            try await store.evict(on: app.db)
            await eventLog.recordProductRowsUpdated(product: deployment.product)
        } catch {
            await fail(deployment: deployment, error: error, output: output, eventLog: eventLog)
            throw error
        }
    }

    /// Builds and archives a deployment without making it live.
    func runBuild(deployment: Deployment, options: Options, eventLog: OperationEventLog) async throws {

        guard deployment.canStartBuildOperation else { throw OperationError.deploymentCannotBuild }

        let store = BinaryStore(target: config.target)
        guard !store.hasBinary(for: deployment) else { throw OperationError.savedBinaryAlreadyExists }

        try await preparePipelineRow(deployment, status: .building, clearOutput: true, eventLog: eventLog)

        let output = makeOutput(deployment: deployment, eventLog: eventLog, options: options)
        let worker = makeWorker(deployment: deployment, output: output, eventLog: eventLog)

        do {
            await output.start()
            try await worker.checkout()
            try await worker.build()
            try await worker.save(to: store)
            await output.flush()

            deployment.finishedAt = .now
            deployment.status = .built
            deployment.output = await output.transcript
            await output.close()
            
            try await deployment.save(on: app.db)
            await eventLog.recordRowUpdated(deploymentID: deployment.id)
        } catch {
            await fail(deployment: deployment, error: error, output: output, eventLog: eventLog)
            throw error
        }
    }

    /// Restores an archived binary and makes that deployment live.
    func runSavedBinary(deployment: Deployment, options: Options, eventLog: OperationEventLog) async throws {

        guard deployment.canStartRestoreOperation else { throw OperationError.deploymentCannotRunSavedBinary }

        let store = BinaryStore(target: config.target)
        guard store.hasBinary(for: deployment) else { throw OperationError.savedBinaryMissing }

        try await preparePipelineRow(deployment, status: .restoring, clearOutput: false, eventLog: eventLog)

        let priorOutput = deployment.output ?? ""
        let output = makeOutput(deployment: deployment, eventLog: eventLog, options: options, priorTranscript: priorOutput)
        let worker = makeWorker(deployment: deployment, output: output, eventLog: eventLog)

        do {
            await output.start()
            try await worker.restore(from: store)
            try await worker.restart()
            deployment.finishedAt = .now
            deployment.output = await output.transcript
            await output.close()

            try await store.syncMetadata(for: deployment, on: app.db)
            try await deployment.setCurrent(on: app.db)
            try await store.evict(on: app.db)
            await eventLog.recordProductRowsUpdated(product: deployment.product)
        } catch {
            await fail(deployment: deployment, error: error, output: output, eventLog: eventLog)
            throw error
        }
    }

    /// Runs `swift test` as an audit and restores the deployment lifecycle status afterwards.
    func runTest(deployment: Deployment, options: Options, eventLog: OperationEventLog) async throws {

        guard deployment.canStartTestOperation else { throw OperationError.deploymentCannotTest }

        let priorStatus = deployment.status
        let priorOutput = deployment.output ?? ""

        deployment.status = .testing
        deployment.testStartedAt = .now
        try await deployment.save(on: app.db)
        await eventLog.recordRowUpdated(deploymentID: deployment.id)

        let output = makeOutput(deployment: deployment, eventLog: eventLog, options: options, priorTranscript: priorOutput)
        let worker = makeWorker(deployment: deployment, output: output, eventLog: eventLog)

        do {
            await output.start()
            try await worker.checkout()
            try await worker.test()
            await output.flush()

            deployment.status = priorStatus
            deployment.testStartedAt = nil
            deployment.lastTestOutcome = true
            deployment.output = await output.transcript
            await output.close()
            
            try await deployment.save(on: app.db)
            await eventLog.recordRowUpdated(deploymentID: deployment.id)
        } catch {
            await output.appendError(error)
            await output.flush()
            deployment.output = await output.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            deployment.status = priorStatus
            deployment.testStartedAt = nil
            deployment.lastTestOutcome = false
            await output.close()
            
            try? await deployment.save(on: app.db)
            await eventLog.recordRowUpdated(deploymentID: deployment.id)
            throw error
        }
    }

    /// Deletes a deployment row after enforcing live-row protection.
    func runDelete(deployment: Deployment, eventLog: OperationEventLog) async throws {

        guard !deployment.isLive else { throw OperationError.liveDeploymentCannotBeDeleted }
        try await deployment.delete(on: app.db)
        await eventLog.recordRowDeleted(deploymentID: deployment.id)
    }

    /// Removes a saved binary and returns the row to the pushed state.
    func runRemoveBinary(deployment: Deployment, eventLog: OperationEventLog) async throws {

        guard !deployment.isLive else { throw OperationError.liveDeploymentBinaryCannotBeRemoved }
        guard deployment.hasSavedBinary else { throw OperationError.savedBinaryMissing }

        let store = BinaryStore(target: config.target)
        guard store.hasBinary(for: deployment) else { throw OperationError.savedBinaryMissing }

        try store.deleteBinary(for: deployment)
        deployment.binarySizeMB = nil
        deployment.isManuallySaved = false
        deployment.output = nil
        deployment.status = .pushed
        try await deployment.save(on: app.db)
        await eventLog.recordRowUpdated(deploymentID: deployment.id)
    }

}

private extension Deployment {

    /// Engine-level deployability excludes UI-only global lock state because callers already hold the lock.
    var canStartPipelineOperation: Bool {
        switch displayStatus {
            case .building, .testing, .restoring, .running: false
            default: true
        }
    }

    /// Engine-level build eligibility for an operation that already owns the global lock.
    var canStartBuildOperation: Bool {
        !isLive && canStartPipelineOperation && !hasSavedBinary
    }

    /// Engine-level restore eligibility for an operation that already owns the global lock.
    var canStartRestoreOperation: Bool {
        !isLive && canStartPipelineOperation && hasSavedBinary
    }

    /// Engine-level test eligibility for an operation that already owns the global lock.
    var canStartTestOperation: Bool {
        switch displayStatus {
            case .building, .testing, .restoring: false
            default: true
        }
    }

}

private extension OperationEngine {

    /// Preserves automatic-mode drain semantics from webhook and boot-triggered deployment.
    func runAutomaticQueue(
        startingWith deployment: Deployment,
        options: Options,
        eventLog: OperationEventLog
    ) async throws {

        var current = deployment
        var lastSuccessful: (deployment: Deployment, transcript: String)?
        let store = BinaryStore(target: config.target)

        while true {
            try await preparePipelineRow(current, status: .building, clearOutput: true, eventLog: eventLog)

            let output = makeOutput(deployment: current, eventLog: eventLog, options: options)
            let worker = makeWorker(deployment: current, output: output, eventLog: eventLog)

            do {
                await output.start()
                try await worker.checkout()
                try await runInlineTestIfNeeded(deployment: current, worker: worker, eventLog: eventLog, policy: options.testPolicy)
                try await worker.build()
                try await worker.move()
                await output.flush()
            } catch {
                await fail(deployment: current, error: error, output: output, eventLog: eventLog)
                if let last = lastSuccessful {
                    try await finalizePreviouslyBuilt(last.deployment, priorTranscript: last.transcript, store: store, eventLog: eventLog)
                }
                throw error
            }

            guard let next = try await nextQueuedDeployment(after: current) else {
                try await finalizeBuilt(current, output: output, store: store, eventLog: eventLog)
                return
            }

            current.finishedAt = .now
            current.status = .built
            current.output = await output.transcript
            try await current.save(on: app.db)
            await eventLog.recordRowUpdated(deploymentID: current.id)

            let transcript = await output.transcript
            await output.close()

            lastSuccessful = (current, transcript)
            current = next
        }
    }

    /// Restarts onto a built deployment whose output stream is still open.
    func finalizeBuilt(
        _ deployment: Deployment,
        output: OperationEventOutput,
        store: BinaryStore,
        eventLog: OperationEventLog
    ) async throws {

        let worker = makeWorker(deployment: deployment, output: output, eventLog: eventLog)

        do {
            try await worker.restart()
            try await worker.deploy(to: store)
            await output.flush()

            deployment.finishedAt = .now
            deployment.output = await output.transcript
            await output.close()

            try await deployment.setCurrent(on: app.db)
            try await store.evict(on: app.db)
            await eventLog.recordProductRowsUpdated(product: deployment.product)
        } catch {
            await fail(deployment: deployment, error: error, output: output, eventLog: eventLog)
            throw error
        }
    }

    /// Restarts onto an earlier successful build after a later automatic candidate failed.
    func finalizePreviouslyBuilt(
        _ deployment: Deployment,
        priorTranscript: String,
        store: BinaryStore,
        eventLog: OperationEventLog
    ) async throws {

        let output = makeOutput(deployment: deployment, eventLog: eventLog, options: Options(), priorTranscript: priorTranscript)
        let worker = makeWorker(deployment: deployment, output: output, eventLog: eventLog)

        do {
            await output.start()
            try await worker.restart()
            try await worker.deploy(to: store)
            
            deployment.finishedAt = .now
            deployment.output = await output.transcript
            await output.close()
            
            try await deployment.setCurrent(on: app.db)
            try await store.evict(on: app.db)
            await eventLog.recordProductRowsUpdated(product: deployment.product)
        } catch {
            await fail(deployment: deployment, error: error, output: output, eventLog: eventLog)
            throw error
        }
    }

}

private extension OperationEngine {

    /// Applies the transient status used while a mutating pipeline action runs.
    func preparePipelineRow(
        _ deployment: Deployment,
        status: Deployment.Status,
        clearOutput: Bool,
        eventLog: OperationEventLog
    ) async throws {

        deployment.startedAt = .now
        deployment.status = status
        deployment.finishedAt = nil
        if clearOutput { deployment.output = nil }

        try await deployment.save(on: app.db)
        await eventLog.recordRowUpdated(deploymentID: deployment.id)
    }

    /// Creates the caller-appropriate output fanout without splitting the deployment engine.
    func makeOutput(
        deployment: Deployment,
        eventLog: OperationEventLog,
        options: Options,
        priorTranscript: String = ""
    ) -> OperationEventOutput {
        .init(
            app: app,
            eventLog: eventLog,
            deployment: deployment,
            priorTranscript: priorTranscript,
            mistSink: origin == .server ? OperationEventMistOutputSink(app: app, deployment: deployment) : nil,
            consoleSink: options.consoleSink
        )
    }

    /// Server-origin operations use direct Mist delivery and do not need durable bridge rows after completion.
    func cleanupServerOperation(_ operation: Operation) async {
        guard origin == .server else { return }
        await OperationRecovery.cleanupTerminalOperation(operation, on: app.db)
    }

    /// Runs inline tests according to the target default and per-job override.
    func runInlineTestIfNeeded(
        deployment: Deployment,
        worker: Worker,
        eventLog: OperationEventLog,
        policy: TestPolicy
    ) async throws {

        let shouldRun = switch policy {
            case .configured: config.target.testing
            case .forceEnabled: true
            case .forceDisabled: false
        }

        guard shouldRun else { return }

        if policy == .configured && deployment.lastTestOutcome == true {
            await worker.stream?.appendLabel("swift test — already passed")
            return
        }

        do {
            deployment.status = .testing
            try await deployment.save(on: app.db)
            await eventLog.recordRowUpdated(deploymentID: deployment.id)
            
            try await worker.test()
            
            deployment.lastTestOutcome = true
            deployment.status = .building
            try await deployment.save(on: app.db)
            await eventLog.recordRowUpdated(deploymentID: deployment.id)
        } catch {
            deployment.lastTestOutcome = false
            try? await deployment.save(on: app.db)
            await eventLog.recordRowUpdated(deploymentID: deployment.id)
            throw error
        }
    }

    /// Marks the row failed and persists the transcript after a streaming operation throws.
    func fail(
        deployment: Deployment,
        error: Swift.Error,
        output: OperationEventOutput,
        eventLog: OperationEventLog
    ) async {

        await output.appendError(error)
        await output.flush()

        deployment.status = .failed
        deployment.finishedAt = .now
        deployment.output = await output.transcript.trimmingCharacters(in: .whitespacesAndNewlines)

        await output.close()
        try? await deployment.save(on: app.db)
        await eventLog.recordRowUpdated(deploymentID: deployment.id)
    }

    /// Creates a worker whose service-status changes are visible to both event stream and panel state.
    func makeWorker(
        deployment: Deployment,
        output: OperationEventOutput?,
        eventLog: OperationEventLog
    ) -> Worker {
        .init(
            deployment: deployment,
            target: config.target,
            app: app,
            stream: output,
            environment: config.deploymentEnvironment,
            onStatusChange: { status in
                try? await eventLog.record(.serviceStatus, deploymentID: deployment.id, payload: status.rawValue)
                await onStatusChange(status)
            }
        )
    }

}

private extension OperationEngine {

    /// Returns the most recent canceled deployment queued after the given one, preserving automatic drain semantics.
    func nextQueuedDeployment(after deployment: Deployment) async throws -> Deployment? {

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

    /// Returns true if newer successful work already made an automatic candidate stale.
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
                    .filter(\.$status, .equal, .built)
                    .filter(\.$status, .equal, .running)
            }
            .first() != nil

        return isSuperseded
    }

}
