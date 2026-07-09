import Vapor

extension OperationEngine {

    /// Builds and archives a deployment without making it live.
    func runBuild(deployment: Deployment, options: Options, recorder: OperationEventRecorder) async throws {

        guard deployment.eligibility(for: .build, holdingLock: true).isAvailable else {
            throw Operation.Error.deploymentCannotBuild
        }

        let store = BinaryStore(target: config.target)
        guard !store.hasBinary(for: deployment) else { throw Operation.Error.savedBinaryAlreadyExists }

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

}
