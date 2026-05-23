import Vapor
import Fluent
import FluentSQLiteDriver

extension Deployment {

    static var migrations: [Migration] { [Table()] }

    struct Table: AsyncMigration {

        func prepare(on database: Database) async throws {

            try await database.schema(Deployment.schema)
                .id()
                .field("created_at", .datetime)
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

}
