import Vapor

public struct DeployerWorker: Sendable {
    
    let deployment: Deployment
    let target: TargetConfiguration
    let app: Application
    
}

extension DeployerWorker {
    
    func pull() async throws {
        try await execute("git pull")
    }

    func build() async throws {
        try await execute("swift build -c \(target.buildMode)")
    }

    func restart() async throws {
        try await execute("supervisorctl restart \(deployment.productName)")
    }

    func move() async throws {
        
        let eventLoop = app.eventLoopGroup.any()
        let threadPool = app.threadPool

        let buildPath = "\(target.workingDirectory)/.build/\(target.buildMode)/\(deployment.productName)"
        let deployDir = "\(target.workingDirectory)/deploy"
        let deployPath = "\(deployDir)/\(deployment.productName)"
        let backupPath = "\(deployDir)/\(deployment.productName).old"

        try await threadPool.runIfActive(eventLoop: eventLoop) {
            let fileManager = FileManager.default
            try fileManager.createDirectory(atPath: deployDir, withIntermediateDirectories: true)

            guard fileManager.fileExists(atPath: buildPath) else {
                throw PipelineError.moveError("New binary not found at \(buildPath)")
            }

            if fileManager.fileExists(atPath: backupPath) {
                try fileManager.removeItem(atPath: backupPath)
            }
            
            if fileManager.fileExists(atPath: deployPath) {
                try fileManager.moveItem(atPath: deployPath, toPath: backupPath)
            }

            do {
                try fileManager.moveItem(atPath: buildPath, toPath: deployPath)
                if fileManager.fileExists(atPath: backupPath) {
                    try? fileManager.removeItem(atPath: backupPath)
                }
            } catch {
                let moveError = error

                if fileManager.fileExists(atPath: backupPath) {
                    do {
                        if fileManager.fileExists(atPath: deployPath) {
                            try fileManager.removeItem(atPath: deployPath)
                        }
                        try fileManager.moveItem(atPath: backupPath, toPath: deployPath)
                    } catch {
                        let rollbackError = error

                        throw PipelineError.moveError(
                            """
                            Deployment failed: '\(moveError.localizedDescription)'.
                            Rollback failed: '\(rollbackError.localizedDescription)'.
                            """
                        )
                    }
                }

                throw PipelineError.moveError(
                    """
                    Deployment failed: '\(moveError.localizedDescription)'.
                    Rollback successfull.
                    """
                )
            }
        }.get()
    }
    
}

extension DeployerWorker {
    
    func execute(_ command: String) async throws {
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["bash", "-c", command]
            process.currentDirectoryURL = URL(fileURLWithPath: target.workingDirectory)
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            process.terminationHandler = { [pipe, process] _ in
                guard process.terminationStatus != 0 else { return continuation.resume(returning: ()) }
                let output = String(
                    data: (try? pipe.fileHandleForReading.readToEnd()) ?? Data(),
                    encoding: .utf8)
                let error = PipelineError.executeError("Execution of '\(command)' failed with output:\n\n'\(output ?? "NO OUTPUT" )'")
                return continuation.resume(throwing: error)
            }
            
            do {
                try process.run()
            } catch {
                let error = PipelineError.initiateError("Start of '\(command)' failed with ourput:\n'\(error.localizedDescription)'")
                continuation.resume(throwing: error)
            }
        }
    }
}

extension DeployerWorker {
    
    enum PipelineError: Error, LocalizedError {

        case initiateError(String)
        case executeError(String)
        case moveError(String)
        
        var errorDescription: String? {
            switch self {
                case .initiateError(let message): "Pipeline initiate error: \(message)"
                case .executeError(let message): "Pipeline execute error: \(message)"
                case .moveError(let message): "Pipeline move error: \(message)"
            }
        }
        
    }
    
}
