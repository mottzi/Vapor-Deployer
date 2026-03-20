import Foundation

// MARK: - Supervisor Status Enumeration

extension DeployerShell.Supervisor {

    /// An exhaustive, type-safe representation of `supervisorctl` process states.
    /// Maps directly to the status strings reported by Supervisor.
    public enum Status: String, Codable, Equatable, Sendable
    {
        case starting  = "STARTING"
        case running   = "RUNNING"
        case backoff   = "BACKOFF"
        case stopping  = "STOPPING"
        case stopped   = "STOPPED"
        case exited    = "EXITED"
        case fatal     = "FATAL"
        case unknown   = "UNKNOWN"

        /// A lowercase display label suitable for UI rendering (e.g. "running", "stopping").
        public var label: String { rawValue.lowercased() }

        /// Whether this status represents a process that is actively running.
        public var isRunning: Bool { self == .running }

        /// Whether this status represents an ephemeral transition state.
        public var isTransitioning: Bool { self == .starting || self == .stopping }
    }

}

// MARK: - Supervisor Commands

extension DeployerShell {
    
    struct Supervisor {

        /// Query the granular process status for a named product.
        /// Parses the output of `supervisorctl status <product>` and maps it
        /// to the `Status` enumeration. Returns `.unknown` if parsing fails.
        static func status(product: String) async -> Status {
            guard let output = (try? await DeployerShell.execute("supervisorctl status \(product)")) else {
                return .unknown
            }

            // supervisorctl status output format:
            // <name>    <STATE>    pid <pid>, uptime <time>
            // e.g.: "mottzi   RUNNING   pid 1234, uptime 0:01:23"
            let tokens = output.split(whereSeparator: { $0.isWhitespace })
            guard tokens.count >= 2 else { return .unknown }

            let stateString = String(tokens[1])
            return Status(rawValue: stateString) ?? .unknown
        }

        /// Legacy convenience: returns `true` if the product is in the RUNNING state.
        static func isRunning(product: String) async -> Bool {
            let currentStatus = await status(product: product)
            return currentStatus.isRunning
        }

        static func start(product: String) async throws {
            try await DeployerShell.execute("supervisorctl start \(product)")
        }

        static func restart(product: String) async throws {
            try await DeployerShell.execute("supervisorctl restart \(product)")
        }

        static func stop(product: String) async throws {
            try await DeployerShell.execute("supervisorctl stop \(product)")
        }

    }
    
}

// MARK: - Shell Execution

struct DeployerShell {
    
    @discardableResult static func execute(_ command: String, directory: String? = nil) async throws -> String {
        
        try await Task.detached {
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["bash", "-c", command]
            if let directory { process.currentDirectoryURL = URL(fileURLWithPath: directory) }

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            pipe.fileHandleForReading.closeFile()

            let output = String(data: data, encoding: .utf8) ?? ""
            guard process.terminationStatus == 0 else { throw ShellError.failed(command: command, output: output) }
            return output
        }.value
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
