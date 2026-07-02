import Vapor
import Fluent

extension OperationEngine {

    /// Preserves automatic-mode drain semantics from webhook and boot-triggered deployment.
    func runAutomaticQueue(
        startingWith deployment: Deployment,
        options: Options,
        recorder: OperationEventRecorder
    ) async throws {

        var current = deployment
        var lastSuccessful: (deployment: Deployment, transcript: String)?
        let store = DeploymentBinaryStore(target: config.target)

        while true {
            try await preparePipelineRow(current, status: .building, clearOutput: true, recorder: recorder)

            let output = makeOutput(deployment: current, recorder: recorder, options: options)
            let worker = makeWorker(deployment: current, output: output, recorder: recorder)

            do {
                await output.open()
                try await worker.checkout()
                try await runInlineTestIfNeeded(deployment: current, worker: worker, recorder: recorder, policy: options.testPolicy)
                try await worker.build()
                try await worker.move()
            } catch {
                await fail(deployment: current, error: error, output: output, recorder: recorder)
                if let last = lastSuccessful {
                    try await finalizePreviouslyBuilt(last.deployment, priorTranscript: last.transcript, store: store, recorder: recorder)
                }
                throw error
            }

            guard let next = try await nextQueuedDeployment(after: current) else {
                try await finalizeBuilt(current, output: output, store: store, recorder: recorder)
                return
            }

            current.finishedAt = .now
            current.status = .built
            current.output = await output.transcript
            try await current.save(on: app.db)
            await recorder.recordRowUpdated(deploymentID: current.id)

            let transcript = await output.transcript
            await output.close()

            lastSuccessful = (current, transcript)
            current = next
        }
    }

    /// Restarts onto a built deployment whose output stream is still open.
    private func finalizeBuilt(
        _ deployment: Deployment,
        output: OperationOutputStream,
        store: DeploymentBinaryStore,
        recorder: OperationEventRecorder
    ) async throws {

        let worker = makeWorker(deployment: deployment, output: output, recorder: recorder)

        do {
            try await worker.restart()
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

    /// Restarts onto an earlier successful build after a later automatic candidate failed.
    private func finalizePreviouslyBuilt(
        _ deployment: Deployment,
        priorTranscript: String,
        store: DeploymentBinaryStore,
        recorder: OperationEventRecorder
    ) async throws {

        let output = makeOutput(deployment: deployment, recorder: recorder, options: Options(), priorTranscript: priorTranscript)
        let worker = makeWorker(deployment: deployment, output: output, recorder: recorder)

        do {
            await output.open()
            try await worker.restart()
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

    /// Returns the most recent canceled deployment queued after the given one, preserving automatic drain semantics.
    private func nextQueuedDeployment(after deployment: Deployment) async throws -> Deployment? {

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
    private func isSuperseded(_ deployment: Deployment) async throws -> Bool {

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
