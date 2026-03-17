import Vapor
import Fluent
import FluentSQLiteDriver
import Mist

extension Deployer {

    func useProductStatusPolling(config: DeployerConfiguration) {
        
        for target in [config.serverTarget, config.deployerTarget] {
            Task.detached { [app] in
                let isRunning = await Supervisor.isRunning(product: target.productName)
                try? await DeployerProductStatus.upsert(productName: target.productName, isRunning: isRunning, on: app.db)

                while !app.didShutdown {
                    try? await Task.sleep(for: .seconds(3))
                    guard !app.didShutdown else { break }
                    let isRunning = await Supervisor.isRunning(product: target.productName)
                    try? await DeployerProductStatus.upsert(productName: target.productName, isRunning: isRunning, on: app.db)
                }
            }
        }
    }

}

final class DeployerProductStatus: Mist.Model, Content, @unchecked Sendable {

    static let schema = "product_statuses"

    @ID(key: .id) var id: UUID?
    @Field(key: "product_name") var productName: String
    @Field(key: "is_running") var isRunning: Bool

    init() {}

    init(productName: String, isRunning: Bool) {
        self.productName = productName
        self.isRunning   = isRunning
    }

}

extension DeployerProductStatus {

    struct Table: AsyncMigration {

        func prepare(on database: Database) async throws {
            try await database.schema(DeployerProductStatus.schema)
                .id()
                .field("product_name", .string, .required)
                .field("is_running", .bool, .required, .sql(.default(false)))
                .create()
        }

        func revert(on database: Database) async throws {
            try await database.schema(DeployerProductStatus.schema).delete()
        }

    }

}

extension DeployerProductStatus {

    static func upsert(productName: String, isRunning: Bool, on db: Database) async throws {

        let existing = try await DeployerProductStatus.query(on: db)
            .filter(\.$productName == productName)
            .first()
        
        if let existing {
            guard existing.isRunning != isRunning else { return }
            existing.isRunning = isRunning
            try await existing.save(on: db)
        } else {
            let new = DeployerProductStatus(productName: productName, isRunning: isRunning)
            try await new.save(on: db)
        }
    }

}

struct Supervisor {

    static func isRunning(product: String) async -> Bool {
        guard let output = (try? await shell("supervisorctl status \(product)")) else { return false }
        return output.contains("RUNNING")
    }

    static func restart(product: String) async throws {
        try await shell("supervisorctl restart \(product)")
    }

    static func stop(product: String) async throws {
        try await shell("supervisorctl stop \(product)")
    }

}

extension Supervisor {
    
    @discardableResult
    static func shell(_ command: String, workingDirectory: String? = nil) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["bash", "-c", command]
            if let workingDirectory {
                process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
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
    
}
