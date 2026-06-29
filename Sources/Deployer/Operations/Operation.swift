import Vapor
import Fluent

/// Durable record for a mutating operation that may be executed by either the panel process or a CLI process.
final class Operation: Model, @unchecked Sendable {

    static let schema = "operations"

    @ID(key: .id) var id: UUID?
    @Enum(key: "kind") var kind: Kind
    @Enum(key: "origin") var origin: Origin
    @Field(key: "product") var product: String
    @OptionalField(key: "deployment_id") var deploymentID: UUID?
    @Enum(key: "status") var status: Status
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?
    @Timestamp(key: "started_at", on: .none) var startedAt: Date?
    @Timestamp(key: "finished_at", on: .none) var finishedAt: Date?

    init() { }

    init(kind: Kind, origin: Origin, product: String, deploymentID: UUID?) {
        self.kind = kind
        self.origin = origin
        self.product = product
        self.deploymentID = deploymentID
        self.status = .running
        self.startedAt = .now
    }

}

extension Operation {

    enum Kind: String, Codable, Sendable {
        case deploy
        case build
        case run
        case test
        case delete
        case removeBinary = "remove-binary"
        case update
        case targetStop = "target-stop"
        case targetRestart = "target-restart"
    }

    enum Origin: String, Codable, Sendable {
        case server
        case cli
    }

    enum Status: String, Codable, Sendable {
        case running
        case completed
        case failed
    }

}

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

    enum EventType: String, Codable, Sendable {
        case started
        case rowUpdated = "row-updated"
        case rowDeleted = "row-deleted"
        case logAppended = "log-appended"
        case serviceStatus = "service-status"
        case completed
        case failed
    }

}
