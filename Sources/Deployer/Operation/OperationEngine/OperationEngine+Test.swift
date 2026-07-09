import Vapor

extension OperationEngine {

    /// Runs `swift test` as an audit and restores the deployment lifecycle status afterwards.
    func runTest(deployment: Deployment, options: Options, recorder: OperationEventRecorder) async throws {

        guard deployment.eligibility(for: .test, holdingLock: true).isAvailable else {
            throw Operation.Error.deploymentCannotTest
        }

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

}
