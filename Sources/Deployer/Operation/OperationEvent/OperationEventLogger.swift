import Vapor
import Fluent

/// Ordered event logger for a single operation.
actor OperationEventLogger {
    
    let app: Application
    let operation: Operation
    private let operationID: UUID
    
    private var nextSequence: Int
    
    init(app: Application, operation: Operation) async throws {
        
        self.app = app
        self.operation = operation
        
        guard let operationID = operation.id else { throw OperationError.operationIDMissing }
        self.operationID = operationID
        
        let lastSequence = try await OperationEvent.query(on: app.db)
            .filter(\.$operationID, .equal, operationID)
            .sort(\.$sequence, .descending)
            .first()?
            .sequence
        ?? 0
        
        self.nextSequence = lastSequence + 1
    }
    
    /// Persists the next CLI-origin event in sequence for server-side Mist replay.
    func record(
        _ type: OperationEvent.EventType,
        deploymentID: UUID? = nil,
        payload: String? = nil
    ) async throws {
        
        guard operation.origin == .cli else { return }
        
        let event = OperationEvent(
            operationID: operationID,
            sequence: nextSequence,
            type: type,
            deploymentID: deploymentID,
            payload: payload
        )
        
        nextSequence += 1
        
        try await event.save(on: app.db)
    }
    
}

extension OperationEventLogger {

    /// Emits a row refresh for the operation's deployment when one is known.
    func recordRowUpdated(deploymentID: UUID?) async {
        do { try await record(.rowUpdated, deploymentID: deploymentID) }
        catch { app.logger.error("Failed to record operation row update: \(error.localizedDescription)") }
    }

    /// Emits a row deletion for CLI-origin deletes so an online panel can remove the instance.
    func recordRowDeleted(deploymentID: UUID?) async {
        do { try await record(.rowDeleted, deploymentID: deploymentID) }
        catch { app.logger.error("Failed to record operation row deletion: \(error.localizedDescription)") }
    }

    /// Emits row refreshes for every row of a product after live-status changes.
    func recordProductRowsUpdated(product: String) async {
        do {
            let deployments = try await Deployment.query(on: app.db)
                .filter(\.$product, .equal, product)
                .all()

            for deployment in deployments {
                try await record(.rowUpdated, deploymentID: deployment.id)
            }
        } catch {
            app.logger.error("Failed to record product row updates: \(error.localizedDescription)")
        }
    }

    /// Marks the operation terminal and records its terminal event.
    func finishOperation(_ status: Operation.Status, deploymentID: UUID?) async {
        do {
            try await record(status == .completed ? .completed : .failed, deploymentID: deploymentID)
            operation.status = status
            operation.finishedAt = .now
            try await operation.save(on: app.db)
        } catch {
            app.logger.error("Failed to finish operation: \(error.localizedDescription)")
        }
    }

}
