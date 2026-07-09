import Vapor

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

    /// Restarts the target, verifies health unless skipped, and rolls back to the predecessor on probe failure.
    func activateLiveBinary(
        worker: OperationWorker,
        deployment: Deployment,
        options: Options
    ) async throws {

        try await worker.restart()

        guard !options.skipHealthCheck else {
            try await worker.cleanupPredecessorBackup()
            return
        }

        do {
            try await worker.verifyHealth()
            try await worker.cleanupPredecessorBackup()
        } catch {
            let liveDeployment = try? await Deployment.getCurrent(named: deployment.product, on: app.db)
            let predecessorSHA = liveDeployment.flatMap { String($0.commitID.prefix(7)) } ?? "unknown"
            let currentSHA = String(deployment.commitID.prefix(7))

            await worker.stream?.appendLabel("Health Check Failure")
            await worker.stream?.append(
                "Deployment unhealthy (\(currentSHA))\nRollback to predecessor (\(currentSHA) -> \(predecessorSHA))...\n"
            )

            try? await worker.restorePredecessorBackup()
            try? await worker.restart(overrideSHA: predecessorSHA)
            throw error
        }
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

    /// Completes the promotion-finalization sequence by assigning outputs, closing the stream, setting current, evicting the binary store, and notifying the recorder.
    func completePromotion(
        _ deployment: Deployment,
        output: OperationOutputStream,
        store: BinaryStore,
        recorder: OperationEventRecorder,
        syncMetadata: Bool = false
    ) async throws {

        deployment.finishedAt = .now
        deployment.output = await output.transcript
        await output.close()

        if syncMetadata {
            try await store.syncMetadata(for: deployment, on: app.db)
        }

        try await deployment.setCurrent(on: app.db)
        try await store.evict(on: app.db)
        await recorder.recordProductRowsUpdated(product: deployment.product)
    }

}

