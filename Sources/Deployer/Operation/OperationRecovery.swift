import Vapor
import Fluent

/// Shared repair path for open operations whose owning process no longer holds the operation lock.
enum OperationRecovery {

    /// Repairs abandoned transient rows unless an operation is actively holding the lock.
    static func repairAbandonedOperations(app: Application, config: Configuration) async {

        guard let installDirectory = try? Configuration.getExecutableURL().deletingLastPathComponent() else { return }
        guard !OperationLock.isHeld(installDirectory: installDirectory) else { return }

        do {
            let operations = try await Operation.query(on: app.db)
                .filter(\.$product, .equal, config.target.name)
                .filter(\.$status, .equal, .running)
                .all()

            for operation in operations {
                try await repair(operation: operation, app: app)
            }
        } catch {
            app.logger.error("Failed to repair abandoned operations: \(error.localizedDescription)")
        }
    }

    /// Deletes terminal operation event rows after the server has had a chance to consume them.
    static func cleanupTerminalOperation(_ operation: Operation, on database: Database) async {
        
        guard let operationID = operation.id else { return }

        do {
            let events = try await OperationEvent.query(on: database)
                .filter(\.$operationID, .equal, operationID)
                .all()
            for event in events {
                try await event.delete(on: database)
            }
            try await operation.delete(on: database)
        } catch {
            database.logger.error("Failed to clean up operation events: \(error.localizedDescription)")
        }
    }

    /// Transient deployment states are repaired to failed after process death.
    static func isTransient(_ status: Deployment.Status) -> Bool {
        status == .building || status == .testing || status == .restoring
    }

    private static func repair(operation: Operation, app: Application) async throws {

        if let deploymentID = operation.deploymentID,
           let deployment = try await Deployment.find(deploymentID, on: app.db),
           isTransient(deployment.status) {

            let note = "\n\nOperation abandoned; no process holds the deployment operation lock. Marking deployment failed.\n"
            deployment.status = .failed
            deployment.finishedAt = .now
            deployment.testStartedAt = nil
            deployment.output = ((deployment.output ?? "") + note).trimmingCharacters(in: .whitespacesAndNewlines)
            try await deployment.save(on: app.db)
        }

        operation.status = .failed
        operation.finishedAt = .now
        try await operation.save(on: app.db)
        await cleanupTerminalOperation(operation, on: app.db)
    }

}
