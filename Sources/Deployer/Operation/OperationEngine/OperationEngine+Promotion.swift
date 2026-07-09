import Vapor

extension OperationEngine {

    /// Promotes exactly the selected deployment without draining newer queued pushes.
    func runPromote(deployment: Deployment, options: Options, recorder: OperationEventRecorder) async throws {

        // Already-live is a no-op success for operators; other blocked statuses throw.
        if deployment.isLive { return }

        guard deployment.eligibility(for: .deploy, holdingLock: true).isAvailable else {
            throw Operation.Error.deploymentCannotDeploy
        }

        let store = BinaryStore(target: config.target)
        let hasSavedBinary = deployment.hasSavedBinary || store.hasBinary(for: deployment)

        if hasSavedBinary {
            guard options.testPolicy != .forceEnabled else { throw Operation.Error.testingSavedBinaryUnsupported }
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
            try await activateLiveBinary(worker: worker, deployment: deployment, options: options)

            try await worker.deploy(to: store)

            try await completePromotion(deployment, output: output, store: store, recorder: recorder)
        } catch {
            await fail(deployment: deployment, error: error, output: output, recorder: recorder)
            throw error
        }
    }

    /// Restores an archived binary and makes that deployment live.
    func runSavedBinary(deployment: Deployment, options: Options, recorder: OperationEventRecorder) async throws {

        guard deployment.eligibility(for: .runSavedBinary, holdingLock: true).isAvailable else {
            throw Operation.Error.deploymentCannotRunSavedBinary
        }

        let store = BinaryStore(target: config.target)
        guard store.hasBinary(for: deployment) else { throw Operation.Error.savedBinaryMissing }

        try await preparePipelineRow(deployment, status: .restoring, clearOutput: false, recorder: recorder)

        let priorOutput = deployment.output ?? ""
        let output = makeOutput(deployment: deployment, recorder: recorder, options: options, priorTranscript: priorOutput)
        let worker = makeWorker(deployment: deployment, output: output, recorder: recorder)

        do {
            await output.open()
            try await worker.restore(from: store)
            try await activateLiveBinary(worker: worker, deployment: deployment, options: options)

            try await completePromotion(deployment, output: output, store: store, recorder: recorder, syncMetadata: true)
        } catch {
            await fail(deployment: deployment, error: error, output: output, recorder: recorder)
            throw error
        }
    }

}
