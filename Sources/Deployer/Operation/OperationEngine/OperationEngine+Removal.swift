import Vapor

extension OperationEngine {

    /// Deletes a deployment row after enforcing live-row protection.
    func runDelete(deployment: Deployment, recorder: OperationEventRecorder) async throws {

        guard deployment.eligibility(for: .delete, holdingLock: true).isAvailable else {
            throw Operation.Error.liveDeploymentCannotBeDeleted
        }

        try await deployment.delete(on: app.db)
        await recorder.recordRowDeleted(deploymentID: deployment.id)
    }

    /// Removes a saved binary and returns the row to the pushed state.
    func runRemoveBinary(deployment: Deployment, recorder: OperationEventRecorder) async throws {

        guard deployment.eligibility(for: .removeBinary, holdingLock: true).isAvailable else {
            if deployment.isLive {
                throw Operation.Error.liveDeploymentBinaryCannotBeRemoved
            }
            throw Operation.Error.savedBinaryMissing
        }

        let store = BinaryStore(target: config.target)
        guard store.hasBinary(for: deployment) else { throw Operation.Error.savedBinaryMissing }

        try store.deleteBinary(for: deployment)
        deployment.binarySizeMB = nil
        deployment.isManuallySaved = false
        deployment.output = nil
        deployment.status = .pushed
        try await deployment.save(on: app.db)
        await recorder.recordRowUpdated(deploymentID: deployment.id)
    }

}
