import Vapor
import Fluent
import FluentSQLiteDriver

extension OperationEvent {

    static var migrations: [Migration] { [Table()] }

    struct Table: AsyncMigration {

        func prepare(on database: Database) async throws {

            try await database.schema(OperationEvent.schema)
                .id()
                .field("operation_id", .uuid, .required)
                .field("sequence", .int, .required)
                .field("type", .string, .required)
                .field("deployment_id", .uuid)
                .field("payload", .string)
                .field("created_at", .datetime)
                .create()
        }

        func revert(on database: Database) async throws {
            try await database.schema(OperationEvent.schema).delete()
        }

    }

}
