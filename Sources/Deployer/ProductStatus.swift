import Vapor
import Fluent
import FluentSQLiteDriver
import Mist

extension Deployer {

    func useProductStatusPolling(config: DeployerConfiguration) {

        for target in [config.serverTarget, config.deployerTarget] {

            let productName = target.productName

            Task.detached { [app] in

                let initiallyRunning = await SupervisorControl.isRunning(program: productName)
                _ = try? await ProductStatus.upsert(productName: productName, isRunning: initiallyRunning, on: app.db)

                while !app.didShutdown {
                    try? await Task.sleep(for: .seconds(3))
                    guard !app.didShutdown else { break }
                    let isRunning = await SupervisorControl.isRunning(program: productName)
                    _ = try? await ProductStatus.upsert(productName: productName, isRunning: isRunning, on: app.db)
                }
            }
        }
    }

}

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

@discardableResult
func shell(_ command: String, workingDirectory: String? = nil) async throws -> String {
    try await withCheckedThrowingContinuation { continuation in
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["bash", "-c", command]
        
        if let dir = workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: dir)
        }
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        process.terminationHandler = { [pipe, process] _ in
            let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
            let output = String(data: data, encoding: .utf8) ?? ""
            guard process.terminationStatus != 0 else { return continuation.resume(returning: output) }
            continuation.resume(throwing: ShellError.failed(command: command, output: output))
        }
        
        do { try process.run() }
        catch { continuation.resume(throwing: error) }
    }
}

enum ShellError: Error, LocalizedError {
    case failed(command: String, output: String)
    
    var errorDescription: String? {
        switch self {
            case .failed(let command, let output): "'\(command)' failed with output:\n\n'\(output)'"
        }
    }
}

struct SupervisorControl {

    static func isRunning(program: String) async -> Bool {
        let output = (try? await shell("supervisorctl status \(program)")) ?? ""
        return output.contains("RUNNING")
    }

    static func restart(program: String) async throws {
        try await shell("supervisorctl restart \(program)")
    }

    static func stop(program: String) async throws {
        try await shell("supervisorctl stop \(program)")
    }

}
