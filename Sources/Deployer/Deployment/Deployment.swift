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

    init(
        product: String,
        status: Status,
        commitMessage: String,
        commitID: String,
        branch: String
    ) {
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

extension Deployment {

    static var migrations: [Migration] { [Table(), AddCreatedAt()] }

    struct Table: AsyncMigration {

        func prepare(on database: Database) async throws {

            try await database.schema(Deployment.schema)
                .id()
                .field("started_at", .datetime)
                .field("finished_at", .datetime)
                .field("product", .string, .required)
                .field("status", .string, .required)
                .field("is_live", .bool, .required, .sql(.default(false)))
                .field("branch", .string, .required)
                .field("commit_id", .string, .required)
                .field("commit_message", .string, .required)
                .field("output", .string)
                .field("is_manually_saved", .bool, .required, .sql(.default(false)))
                .field("binary_size_mb", .int)
                .field("last_test_outcome", .bool)
                .field("test_started_at", .datetime)
                .create()
        }

        func revert(on database: Database) async throws {
            try await database.schema(Deployment.schema).delete()
        }

    }

    /// Adds `created_at` — the immutable arrival timestamp that drives table order, decoupled from
    /// `started_at` (which is refreshed each time `start()` actually begins a build/restore). Existing
    /// rows are backfilled from `started_at` so historical ordering is preserved.
    struct AddCreatedAt: AsyncMigration {

        func prepare(on database: Database) async throws {

            try await database.schema(Deployment.schema)
                .field("created_at", .datetime)
                .update()

            let deployments = try await Deployment.query(on: database).all()
            for deployment in deployments where deployment.createdAt == nil {
                deployment.createdAt = deployment.startedAt
                try await deployment.save(on: database)
            }
        }

        func revert(on database: Database) async throws {
            try await database.schema(Deployment.schema)
                .deleteField("created_at")
                .update()
        }

    }

}

extension Deployment {

    enum Status: String, Codable, Sendable {
        case pushed
        case testing
        case building
        case restoring
        case canceled
        case failed
        case built
        case running
        case stale
    }
    
}

extension Deployment {
    
    var computedProperties: [String: any SendableEncodable] { [
        "durationString": durationString,
        "displayStatus": displayStatus.rawValue,
        "shortID": shortID,
        "startedAtUnixMs": startedAtUnixMs,
        "canBeDeployed": canBeDeployed,
        "canBuild": canBuild,
        "canRestoreBinary": canRestoreBinary,
        "canTest": canTest,
        "testsPassed": testsPassed,
        "testsFailed": testsFailed,
        "hasSavedBinary": hasSavedBinary,
        "hasDetails": hasDetails,
        "hasLiveOutputStream": hasLiveOutputStream,
        "outputHTML": outputHTML,
    ] }

    var durationString: String? {
        guard let finishedAt, let startedAt else { return nil }
        return String(format: "%.1fs", finishedAt.timeIntervalSince(startedAt))
    }
    
    static let staleThreshold: TimeInterval = 30 * 60

    var displayStatus: Status {
        if (status == .building || status == .restoring || status == .testing),
           let referenceTime = (status == .testing ? (testStartedAt ?? startedAt) : startedAt),
           Date.now.timeIntervalSince(referenceTime) > Self.staleThreshold {
            .stale
        } else {
            status
        }
    }
    
    var shortID: String? { id.map { String($0.uuidString.prefix(8)) } }
    
    var startedAtUnixMs: Int? { startedAt.map { Int($0.timeIntervalSince1970 * 1000) } }

    var canBeDeployed: Bool {
        switch displayStatus {
            case .building: false
            case .testing: false
            case .restoring: false
            case .running: false
            default: true
        }
    }

    var canBuild: Bool {
        canBeDeployed && !hasSavedBinary
    }

    var hasSavedBinary: Bool {
        binarySizeMB != nil
    }

    var canRestoreBinary: Bool {
        canBeDeployed && hasSavedBinary
    }

    /// Test eligibility — permissive. Allowed on every non-actively-transient state, including
    /// `.running` (the live binary is untouched; tests compile into `.build-tests/`). The queue
    /// lock still serializes execution.
    var canTest: Bool {
        switch displayStatus {
            case .building, .testing, .restoring: false
            default: true
        }
    }

    var testsPassed: Bool { lastTestOutcome == true }
    var testsFailed: Bool { lastTestOutcome == false }

    var hasDetails: Bool {
        output != nil || hasLiveOutputStream
    }

    var hasLiveOutputStream: Bool {
        status == .building || status == .testing
    }

    /// HTML-rendered output: escapes user-facing text and, on failure, wraps the failing pipeline section in a red span.
    var outputHTML: String? {
        guard let output, !output.isEmpty else { return nil }
        return status == .failed
            ? Self.wrapFailedSection(in: output)
            : Self.htmlEscape(output)
    }

    private static func htmlEscape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// Wraps the transcript from the last `──── label ────` marker to the end in a span the CSS can color red.
    /// All content (inside and outside the span) is HTML-escaped; only the controlled `<span>` tags are raw.
    private static func wrapFailedSection(in text: String) -> String {
        guard let range = text.range(of: "──── ", options: .backwards) else {
            return htmlEscape(text)
        }
        let before = String(text[..<range.lowerBound])
        let after = String(text[range.lowerBound...])
        return htmlEscape(before)
            + "<span class=\"dp-section--error\">"
            + htmlEscape(after)
            + "</span>"
    }

}

extension Deployment {
    
    func setCurrent(on database: Database) async throws {
        
        self.isLive = true
        self.status = .running
        try await self.save(on: database)

        let oldCurrentDeployments = try await Deployment.query(on: database)
            .filter(\.$isLive, .equal, true)
            .filter(\.$product, .equal, self.product)
            .filter(\.$id, .notEqual, self.id!)
            .all()

        for deployment in oldCurrentDeployments {
            deployment.isLive = false
            deployment.status = .built
            try await deployment.save(on: database)
        }
    }
    
    static func getCurrent(named productName: String, on database: Database) async throws -> Deployment? {
        
        try await Deployment.query(on: database)
            .filter(\.$isLive, .equal, true)
            .filter(\.$product, .equal, productName)
            .first()
    }
    
}
