import Vapor

extension OperationEngine {

    /// Promotes exactly the selected deployment without draining newer queued pushes.
    func runPromote(deployment: Deployment, options: Options, recorder: OperationEventRecorder) async throws {

        if deployment.isLive { return }

        let store = DeploymentBinaryStore(target: config.target)
        let hasSavedBinary = deployment.hasSavedBinary || store.hasBinary(for: deployment)

        if hasSavedBinary {
            guard options.testPolicy != .forceEnabled else { throw OperationError.testingSavedBinaryUnsupported }
            try await runSavedBinary(deployment: deployment, options: options, recorder: recorder)
            return
        }

        try await preparePipelineRow(deployment, status: .building, clearOutput: true, recorder: recorder)

        let output = makeOutput(deployment: deployment, recorder: recorder, options: options)
        let worker = makeWorker(deployment: deployment, output: output, recorder: recorder)

        do {
            await output.open()
            try await worker.checkout()
            try await runInlineTestIfNeeded(deployment: deployment, worker: worker, recorder: recorder, policy: options.testPolicy)
            try await worker.build()
            try await worker.move()
            try await worker.restart()

            if !options.skipHealthCheck {
                do {
                    try await worker.verifyHealth()
                    try await worker.cleanupPredecessorBackup()
                } catch {
                    let liveDeployment = try? await Deployment.getCurrent(named: deployment.product, on: app.db)
                    let predecessorSHA = liveDeployment?.commitID.prefix(7).map { String($0) } ?? "unknown"
                    let currentSHA = String(deployment.commitID.prefix(7))
                    
                    await worker.stream?.appendLabel("Health Check Failure")
                    await worker.stream?.append("Deployment unhealthy (\(currentSHA))\nRollback to predecessor (\(currentSHA) -> \(predecessorSHA))...\n")
                    
                    // Recover backup binary & restart back to original predecessor
                    try? await worker.restorePredecessorBackup()
                    try? await worker.restart(overrideSHA: predecessorSHA)
                    throw error
                }
            } else {
                try await worker.cleanupPredecessorBackup()
            }
            
            try await worker.deploy(to: store)

            deployment.finishedAt = .now
            deployment.output = await output.transcript
            await output.close()

            try await deployment.setCurrent(on: app.db)
            try await store.evict(on: app.db)
            await recorder.recordProductRowsUpdated(product: deployment.product)
        } catch {
            await fail(deployment: deployment, error: error, output: output, recorder: recorder)
            throw error
        }
    }

    /// Builds and archives a deployment without making it live.
    func runBuild(deployment: Deployment, options: Options, recorder: OperationEventRecorder) async throws {

        guard deployment.canStartBuildOperation else { throw OperationError.deploymentCannotBuild }

        let store = DeploymentBinaryStore(target: config.target)
        guard !store.hasBinary(for: deployment) else { throw OperationError.savedBinaryAlreadyExists }

        try await preparePipelineRow(deployment, status: .building, clearOutput: true, recorder: recorder)

        let output = makeOutput(deployment: deployment, recorder: recorder, options: options)
        let worker = makeWorker(deployment: deployment, output: output, recorder: recorder)

        do {
            await output.open()
            try await worker.checkout()
            try await worker.build()
            try await worker.save(to: store)

            deployment.finishedAt = .now
            deployment.status = .built
            deployment.output = await output.transcript
            await output.close()
            
            try await deployment.save(on: app.db)
            await recorder.recordRowUpdated(deploymentID: deployment.id)
        } catch {
            await fail(deployment: deployment, error: error, output: output, recorder: recorder)
            throw error
        }
    }

    /// Restores an archived binary and makes that deployment live.
    func runSavedBinary(deployment: Deployment, options: Options, recorder: OperationEventRecorder) async throws {

        guard deployment.canStartRestoreOperation else { throw OperationError.deploymentCannotRunSavedBinary }

        let store = DeploymentBinaryStore(target: config.target)
        guard store.hasBinary(for: deployment) else { throw OperationError.savedBinaryMissing }

        try await preparePipelineRow(deployment, status: .restoring, clearOutput: false, recorder: recorder)

        let priorOutput = deployment.output ?? ""
        let output = makeOutput(deployment: deployment, recorder: recorder, options: options, priorTranscript: priorOutput)
        let worker = makeWorker(deployment: deployment, output: output, recorder: recorder)

        do {
            await output.open()
            try await worker.restore(from: store)
            try await worker.restart()

            if !options.skipHealthCheck {
                do {
                    try await worker.verifyHealth()
                    try await worker.cleanupPredecessorBackup()
                } catch {
                    await worker.stream?.appendLabel("Health Check Failure")
                    await worker.stream?.append("Deployment unhealthy. Triggering auto-rollback to predecessor...\n")
                    
                    // Recover backup binary & restart back to original predecessor
                    try? await worker.restorePredecessorBackup()
                    try? await worker.restart()
                    throw error
                }
            } else {
                try await worker.cleanupPredecessorBackup()
            }

            deployment.finishedAt = .now
            deployment.output = await output.transcript
            await output.close()

            try await store.syncMetadata(for: deployment, on: app.db)
            try await deployment.setCurrent(on: app.db)
            try await store.evict(on: app.db)
            await recorder.recordProductRowsUpdated(product: deployment.product)
        } catch {
            await fail(deployment: deployment, error: error, output: output, recorder: recorder)
            throw error
        }
    }

    /// Runs `swift test` as an audit and restores the deployment lifecycle status afterwards.
    func runTest(deployment: Deployment, options: Options, recorder: OperationEventRecorder) async throws {

        guard deployment.canStartTestOperation else { throw OperationError.deploymentCannotTest }

        let priorStatus = deployment.status
        let priorOutput = deployment.output ?? ""

        deployment.status = .testing
        deployment.testStartedAt = .now
        try await deployment.save(on: app.db)
        await recorder.recordRowUpdated(deploymentID: deployment.id)

        let output = makeOutput(deployment: deployment, recorder: recorder, options: options, priorTranscript: priorOutput)
        let worker = makeWorker(deployment: deployment, output: output, recorder: recorder)

        do {
            await output.open()
            try await worker.checkout()
            try await worker.test()

            deployment.status = priorStatus
            deployment.testStartedAt = nil
            deployment.lastTestOutcome = true
            deployment.output = await output.transcript
            await output.close()
            
            try await deployment.save(on: app.db)
            await recorder.recordRowUpdated(deploymentID: deployment.id)
        } catch {
            await output.appendError(error)
            deployment.output = await output.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            deployment.status = priorStatus
            deployment.testStartedAt = nil
            deployment.lastTestOutcome = false
            await output.close()
            
            try? await deployment.save(on: app.db)
            await recorder.recordRowUpdated(deploymentID: deployment.id)
            throw error
        }
    }

    /// Deletes a deployment row after enforcing live-row protection.
    func runDelete(deployment: Deployment, recorder: OperationEventRecorder) async throws {

        guard !deployment.isLive else { throw OperationError.liveDeploymentCannotBeDeleted }
        try await deployment.delete(on: app.db)
        await recorder.recordRowDeleted(deploymentID: deployment.id)
    }

    /// Removes a saved binary and returns the row to the pushed state.
    func runRemoveBinary(deployment: Deployment, recorder: OperationEventRecorder) async throws {

        guard !deployment.isLive else { throw OperationError.liveDeploymentBinaryCannotBeRemoved }
        guard deployment.hasSavedBinary else { throw OperationError.savedBinaryMissing }

        let store = DeploymentBinaryStore(target: config.target)
        guard store.hasBinary(for: deployment) else { throw OperationError.savedBinaryMissing }

        try store.deleteBinary(for: deployment)
        deployment.binarySizeMB = nil
        deployment.isManuallySaved = false
        deployment.output = nil
        deployment.status = .pushed
        try await deployment.save(on: app.db)
        await recorder.recordRowUpdated(deploymentID: deployment.id)
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

extension OperationEngine {

    /// Applies the transient status used while a mutating pipeline action runs.
    func preparePipelineRow(
        _ deployment: Deployment,
        status: Deployment.Status,
        clearOutput: Bool,
        recorder: OperationEventRecorder
    ) async throws {
        
        deployment.startedAt = .now
        deployment.status = status
        deployment.finishedAt = nil
        if clearOutput { deployment.output = nil }

        try await deployment.save(on: app.db)
        await recorder.recordRowUpdated(deploymentID: deployment.id)
    }

    /// Creates the caller-appropriate output fanout without splitting the deployment engine.
    func makeOutput(
        deployment: Deployment,
        recorder: OperationEventRecorder,
        options: Options,
        priorTranscript: String = ""
    ) -> OperationOutputStream {
        
        OperationOutputStream(
            app: app,
            recorder: recorder,
            deployment: deployment,
            priorTranscript: priorTranscript,
            mistSink: origin == .server ? OperationOutputMistSink(app: app, deployment: deployment) : nil,
            consoleSink: options.consoleSink
        )
    }

    /// Runs inline tests according to the target default and per-job override.
    func runInlineTestIfNeeded(
        deployment: Deployment,
        worker: OperationWorker,
        recorder: OperationEventRecorder,
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
            await recorder.recordRowUpdated(deploymentID: deployment.id)
            
            try await worker.test()
            
            deployment.lastTestOutcome = true
            deployment.status = .building
            try await deployment.save(on: app.db)
            await recorder.recordRowUpdated(deploymentID: deployment.id)
        } catch {
            deployment.lastTestOutcome = false
            try? await deployment.save(on: app.db)
            await recorder.recordRowUpdated(deploymentID: deployment.id)
            throw error
        }
    }

    /// Marks the row failed and persists the transcript after a streaming operation throws.
    func fail(
        deployment: Deployment,
        error: Swift.Error,
        output: OperationOutputStream,
        recorder: OperationEventRecorder
    ) async {

        await output.appendError(error)

        deployment.status = .failed
        deployment.finishedAt = .now
        deployment.output = await output.transcript.trimmingCharacters(in: .whitespacesAndNewlines)

        await output.close()
        try? await deployment.save(on: app.db)
        await recorder.recordRowUpdated(deploymentID: deployment.id)
    }

    /// Creates a worker whose service-status changes are visible to both event stream and panel state.
    func makeWorker(
        deployment: Deployment,
        output: OperationOutputStream?,
        recorder: OperationEventRecorder
    ) -> OperationWorker {
        
        OperationWorker(
            deployment: deployment,
            target: config.target,
            app: app,
            stream: output,
            environment: config.deploymentEnvironment,
            onStatusChange: { status in
                try? await recorder.record(.serviceStatus, deploymentID: deployment.id, payload: status.rawValue)
                await onStatusChange(status)
            }
        )
    }

}
