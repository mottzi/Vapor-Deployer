import Vapor
import Fluent
import FluentSQLiteDriver
import Mist

final class Deployment: Mist.Model, Content, @unchecked Sendable {
    
    static let schema = "deployments"

    @ID(key: .id) var id: UUID?
    @Timestamp(key: "started_at", on: .none) var startedAt: Date?
    @Timestamp(key: "finished_at", on: .none) var finishedAt: Date?
    @Field(key: "product") var product: String
    @Enum(key: "status") var status: Status
    @Field(key: "is_live") var isLive: Bool
    @Field(key: "branch") var branch: String
    @Field(key: "commit_id") var commitID: String
    @Field(key: "commit_message") var commitMessage: String
    @Field(key: "error_message") var errorMessage: String?

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
        self.errorMessage = nil
    }
    
}

extension Deployment {
    
    static var migration: Migration { Table() }
    
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
                .field("error_message", .string)
                .create()
        }

        func revert(on database: Database) async throws {
            try await database.schema(Deployment.schema).delete()
        }
        
    }
    
}

extension Deployment {

    enum Status: String, Codable {
        case pushed
        case running
        case canceled
        case failed
        case success
        case deployed
        case stale
    }
    
}

extension Deployment {
    
    var computedProperties: [String: any Encodable] { [
        "durationString": durationString,
        "displayStatus": displayStatus,
        "shortID": shortID,
        "startedAtUnixMs": startedAtUnixMs,
        "canBeDeployed": canBeDeployed,
    ] }

    var durationString: String? {
        guard let finishedAt, let startedAt else { return nil }
        return String(format: "%.1fs", finishedAt.timeIntervalSince(startedAt))
    }
    
    var displayStatus: Status {
        if status == .running,
           let startedAt,
           Date.now.timeIntervalSince(startedAt) > 1800 {
            .stale
        } else {
            status
        }
    }
    
    var shortID: String? { id.map { String($0.uuidString.prefix(8)) } }
    
    var startedAtUnixMs: Int? { startedAt.map { Int($0.timeIntervalSince1970 * 1000) } }

    var canBeDeployed: Bool {
        switch displayStatus {
            case .running: false
            case .deployed: false
            default: true
        }
    }

}

extension Deployment {
    
    func setCurrent(on database: Database) async throws {
        
        self.isLive = true
        self.status = .deployed
        try await self.save(on: database)

        let oldCurrentDeployments = try await Deployment.query(on: database)
            .filter(\.$isLive, .equal, true)
            .filter(\.$product, .equal, self.product)
            .filter(\.$id, .notEqual, self.id!)
            .all()

        for deployment in oldCurrentDeployments {
            deployment.isLive = false
            deployment.status = .success
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
