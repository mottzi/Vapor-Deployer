import Vapor
import Fluent
import FluentSQLiteDriver
import Mist

final class Deployment: Mist.Model, Content, @unchecked Sendable {

    static let schema = "deployments"

    @ID(key: .id) var id: UUID?
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?
    @Timestamp(key: "started_at", on: .none) var startedAt: Date?
    @Timestamp(key: "finished_at", on: .none) var finishedAt: Date?
    @Field(key: "product") var product: String
    @Enum(key: "status") var status: Status
    @Field(key: "is_live") var isLive: Bool
    @Field(key: "branch") var branch: String
    @Field(key: "commit_id") var commitID: String
    @Field(key: "commit_message") var commitMessage: String
    @Field(key: "output") var output: String?
    @Field(key: "is_manually_saved") var isManuallySaved: Bool
    @OptionalField(key: "binary_size_mb") var binarySizeMB: Int?
    @OptionalField(key: "last_test_outcome") var lastTestOutcome: Bool?
    @OptionalField(key: "test_started_at") var testStartedAt: Date?

    init() { }

    init(product: String, status: Status, commitMessage: String, commitID: String, branch: String) {
        self.product = product
        self.status = status
        self.commitMessage = commitMessage
        self.commitID = commitID
        self.branch = branch
        self.isLive = false
        self.output = nil
        self.isManuallySaved = false
        self.binarySizeMB = nil
        self.lastTestOutcome = nil
        self.testStartedAt = nil
    }

}
