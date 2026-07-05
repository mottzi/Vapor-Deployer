import Vapor
import Fluent

/// Durable event emitted by an operation so an online server can mirror CLI-origin work into Mist.
final class OperationEvent: Model, @unchecked Sendable {

    static let schema = "operation_events"

    @ID(key: .id) var id: UUID?
    @Field(key: "operation_id") var operationID: UUID
    @Field(key: "sequence") var sequence: Int
    @Enum(key: "type") var type: EventType
    @OptionalField(key: "deployment_id") var deploymentID: UUID?
    @OptionalField(key: "payload") var payload: String?
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?

    init() { }

    init(operationID: UUID, sequence: Int, type: EventType, deploymentID: UUID?, payload: String?) {
        self.operationID = operationID
        self.sequence = sequence
        self.type = type
        self.deploymentID = deploymentID
        self.payload = payload
    }

}

extension OperationEvent {

    /// The specific database change or real-time progress update emitted by an active operation.
    enum EventType: String, Codable {

        case outputOpened = "output-opened"
        case rowUpdated = "row-updated"
        case rowDeleted = "row-deleted"
        case logAppended = "log-appended"
        case serviceStatus = "service-status"
        case completed
        case failed

    }

}
