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

    /// The category of mutating deployment or target lifecycle action being tracked.
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

    /// The execution environment that initiated the operation.
    enum Origin: String, Codable, Sendable {
        case server
        case cli
    }

    /// The current execution lifecycle phase of the operation.
    enum Status: String, Codable, Sendable {
        case running
        case completed
        case failed
    }

}
