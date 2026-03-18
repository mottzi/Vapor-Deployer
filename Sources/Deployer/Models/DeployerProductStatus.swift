//import Vapor
//import Fluent
//import FluentSQLiteDriver
import Foundation

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
