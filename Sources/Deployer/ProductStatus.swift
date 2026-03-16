import Vapor
import Fluent
import FluentSQLiteDriver
import Mist

final class ProductStatus: Mist.Model, Content, @unchecked Sendable {

    static let schema = "product_statuses"

    @ID(key: .id)               var id: UUID?
    @Field(key: "product_name") var productName: String
    @Field(key: "is_running")   var isRunning: Bool

    init() {}

    init(productName: String, isRunning: Bool) {
        self.productName = productName
        self.isRunning   = isRunning
    }

}

extension ProductStatus {

    struct Table: AsyncMigration {

        func prepare(on database: Database) async throws {
            try await database.schema(ProductStatus.schema)
                .id()
                .field("product_name", .string, .required)
                .field("is_running",   .bool,   .required, .sql(.default(false)))
                .create()
        }

        func revert(on database: Database) async throws {
            try await database.schema(ProductStatus.schema).delete()
        }

    }

}

extension ProductStatus {

    // No-op when state hasn't changed, preventing spurious Mist listener broadcasts.
    @discardableResult
    static func upsert(productName: String, isRunning: Bool, on db: Database) async throws -> ProductStatus {

        if let existing = try await ProductStatus.query(on: db)
            .filter(\.$productName == productName)
            .first()
        {
            guard existing.isRunning != isRunning else { return existing }
            existing.isRunning = isRunning
            try await existing.save(on: db)
            return existing
        }

        let new = ProductStatus(productName: productName, isRunning: isRunning)
        try await new.save(on: db)
        return new

    }

}
