import Vapor
import Fluent
import FluentSQLiteDriver
import Mist

final class Deployment: Mist.Model, Content, @unchecked Sendable {
    
    static let schema = "deployments"

    @ID(key: .id) var id: UUID?
    @Enum(key: "mode") var mode: Mode
    @Field(key: "product_name") var productName: String
    @Enum(key: "status") var status: Status
    @Field(key: "message") var message: String
    @Field(key: "is_current") var isCurrent: Bool
    @Field(key: "error_message") var errorMessage: String?
    @Timestamp(key: "started_at", on: .create) var startedAt: Date?
    @Timestamp(key: "finished_at", on: .none) var finishedAt: Date?

    init() { }

    init(
        productName: String,
        status: Status,
        message: String,
        mode: Mode = .standard
    ) {
        self.productName = productName
        self.status = status
        self.message = message
        self.isCurrent = false
        self.errorMessage = nil
        self.mode = mode
    }
    
}

extension Deployment {
    
    static var migration: Migration { Table() }
    
    struct Table: AsyncMigration {
        
        func prepare(on database: Database) async throws {
            
            try await database.schema(Deployment.schema)
                .id()
                .field("product_name", .string, .required)
                .field("status", .string, .required)
                .field("message", .string, .required)
                .field("is_current", .bool, .required, .sql(.default(false)))
                .field("error_message", .string)
                .field("started_at", .datetime)
                .field("finished_at", .datetime)
                .field("mode", .string, .required, .sql(.default(Mode.standard.rawValue)))
                .create()
        }

        func revert(on database: Database) async throws {
            try await database.schema(Deployment.schema).delete()
        }
        
    }
    
}

extension Deployment {
    
    enum Mode: String, Codable {
        case standard
        case restartOnly
    }
    
    enum Status: String, Codable, CaseIterable {
        case running
        case canceled
        case failed
        case success
        case deployed
        case stale
    }
    
}

extension Deployment {
    
    var contextExtras: [String: any Encodable] {
        [
            "durationString": durationString,
            "displayStatus": displayStatus,
            "shortID": shortID,
            "startedAtTime": formattedTime,
            "startedAtDate": formattedDate,
        ]
    }

    var durationString: String? {
        guard let finishedAt, let startedAt else { return nil }
        return String(format: "%.1fs", finishedAt.timeIntervalSince(startedAt))
    }

    var shortID: String { String(id?.uuidString.prefix(8) ?? "") }

    var displayStatus: Status {
        guard status == .running,
              let startedAt = startedAt,
              Date.now.timeIntervalSince(startedAt) > 1800
        else { return status }
        
        return .stale
    }
    
    var formattedTime: String? {
        guard let startedAt else { return nil }
        return Deployment.timeFormatter.string(from: startedAt)
    }
    
    var formattedDate: String? {
        guard let startedAt else { return nil }
        return Deployment.timeFormatter.string(from: startedAt)
    }
    
}

extension Deployment {
    
    func setCurrent(on database: Database) async throws {
        
        self.isCurrent = true
        self.status = .deployed
        try await self.save(on: database)

        let oldCurrentDeployments = try await Deployment.query(on: database)
            .filter(\.$isCurrent, .equal, true)
            .filter(\.$productName, .equal, self.productName)
            .filter(\.$id, .notEqual, self.id!)
            .all()

        for deployment in oldCurrentDeployments {
            deployment.isCurrent = false
            deployment.status = .success
            try await deployment.save(on: database)
        }
    }
    
    static func getCurrent(named productName: String, on database: Database) async throws -> Deployment? {
        
        try await Deployment.query(on: database)
            .filter(\.$isCurrent, .equal, true)
            .filter(\.$productName, .equal, productName)
            .first()
    }
    
}

extension Deployment {
    
    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
    
    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd.MM.yy"
        return f
    }()
    
}
