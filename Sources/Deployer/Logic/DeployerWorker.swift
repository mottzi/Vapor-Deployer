import Vapor

public struct DeployerWorker: Sendable {
    
    let deployment: Deployment
    let target: TargetConfiguration
    let app: Application
    
}

extension DeployerWorker {
    
    func pull() async throws {
        try await DeployerShell.execute("git pull", directory: target.workingDirectory)
    }

    func build() async throws {
        try await DeployerShell.execute("swift build -c \(target.buildMode)", directory: target.workingDirectory)
    }

    func restart() async throws {
        try await DeployerShell.Supervisor.restart(product: deployment.productName)
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
                throw MoveError.binaryNotFound(buildPath)
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
                        throw MoveError.deploymentAndRollbackFailed(
                            moveError.localizedDescription,
                            error.localizedDescription
                        )
                    }
                }

                throw MoveError.deploymentFailed(moveError.localizedDescription)
            }
        }.get()
    }
    
}

extension DeployerWorker {
    
    enum MoveError: Error, LocalizedError {
        
        case binaryNotFound(String)
        case deploymentFailed(String)
        case deploymentAndRollbackFailed(String, String)

        var errorDescription: String? {
            switch self {
                case .binaryNotFound(let path): "New binary not found at \(path)"
                case .deploymentFailed(let error): "Deployment failed: '\(error)'. Rollback successful."
                case .deploymentAndRollbackFailed(let error, let rollback): "Deployment failed: '\(error)'. Rollback failed: '\(rollback)'."
            }
        }
        
    }
    
}
