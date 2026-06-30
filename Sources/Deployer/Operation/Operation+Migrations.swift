import Vapor
import Fluent
import FluentSQLiteDriver

extension Operation {

    static var migrations: [Migration] { [Table()] }

    struct Table: AsyncMigration {

        func prepare(on database: Database) async throws {

            try await database.schema(Operation.schema)
                .id()
                .field("kind", .string, .required)
                .field("origin", .string, .required)
                .field("product", .string, .required)
                .field("deployment_id", .uuid)
                .field("status", .string, .required)
                .field("created_at", .datetime)
                .field("started_at", .datetime)
                .field("finished_at", .datetime)
                .create()
        }

        func revert(on database: Database) async throws {
            try await database.schema(Operation.schema).delete()
        }

    }

}
