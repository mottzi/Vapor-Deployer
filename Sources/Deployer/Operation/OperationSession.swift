import Vapor
import Fluent

/// Lifecycle owner for one durable operation and its ordered event stream.
actor OperationSession {
    
    private let app: Application
    private let operation: Operation
    let recorder: OperationEventRecorder
    
    private init(
        app: Application,
        operation: Operation,
        recorder: OperationEventRecorder
    ) {
        self.app = app
        self.operation = operation
        self.recorder = recorder
    }
    
    /// Creates the running operation row and its event recorder.
    static func begin(
        app: Application,
        kind: Operation.Kind,
        origin: Operation.Origin,
        product: String,
        deploymentID: UUID?
    ) async throws -> OperationSession {
        
        let operation = Operation(kind: kind, origin: origin, product: product, deploymentID: deploymentID)
        try await operation.save(on: app.db)
        
        let opID = operation.id?.uuidString ?? "unknown"
        app.logger.info("Operation session started (ID: \(opID))")

        let recorder = try await OperationEventRecorder(app: app, operation: operation)
        return OperationSession(app: app, operation: operation, recorder: recorder)
    }
    
    /// Marks the operation completed and records its terminal event.
    func complete(deploymentID: UUID?) async {
        await finish(.completed, deploymentID: deploymentID)
    }
    
    /// Marks the operation failed and records its terminal event.
    func fail(deploymentID: UUID?) async {
        await finish(.failed, deploymentID: deploymentID)
    }
    
    /// Removes server-origin operation rows after their direct in-process delivery is complete.
    func cleanupIfServerOrigin() async {
        guard operation.origin == .server else { return }
        await OperationRecovery.cleanupTerminalOperation(operation, on: app.db)
    }
    
}

extension OperationSession {
    
    /// Records the terminal event before marking the parent operation terminal.
    private func finish(_ status: Operation.Status, deploymentID: UUID?) async {
        let opID = operation.id?.uuidString ?? "unknown"
        do {
            try await recorder.record(status == .completed ? .completed : .failed, deploymentID: deploymentID)
            operation.status = status
            operation.finishedAt = .now
            try await operation.save(on: app.db)
            app.logger.info("Operation session \(status == .completed ? "completed" : "failed") (ID: \(opID))")
        } catch {
            app.logger.error("Failed to finish operation: \(error.localizedDescription)")
        }
    }
    
}
