import Vapor

struct DeployerWorker: Sendable {
    
    let deployment: Deployment
    let target: TargetConfiguration
    let app: Application
    let onStatusChange: @Sendable (DeployerServiceStatus) async -> Void
    
}

extension DeployerWorker {
    
    func checkout() async throws {
        try await DeployerShell.execute("git fetch origin \(deployment.branch.shellQuoted)", directory: target.directory)
        try await DeployerShell.execute("git checkout --detach \(deployment.commitID.shellQuoted)", directory: target.directory)
    }

    func build() async throws {
        try await DeployerShell.execute("swift build -c \(target.buildMode)", directory: target.directory)
    }
    
    func restart() async throws {
        let manager = app.deployer.serviceManager
        let status = await manager.status(product: deployment.product)
        await onStatusChange(status.isRunning ? .stopping : .starting)
        
        try await manager.restart(product: deployment.product)
        await onStatusChange(.starting)
        
        let finalStatus = await manager.status(product: deployment.product)
        await onStatusChange(finalStatus)
    }

    func move() async throws {

        let eventLoop = app.eventLoopGroup.any()
        let threadPool = app.threadPool

        let buildPath = "\(target.directory)/.build/\(target.buildMode)/\(deployment.product)"
        let deployDir = "\(target.directory)/deploy"
        let deployPath = "\(deployDir)/\(deployment.product)"
        let backupPath = "\(deployDir)/\(deployment.product).old"

        try await threadPool.runIfActive(eventLoop: eventLoop) {
            let fileManager = FileManager.default
            try fileManager.createDirectory(atPath: deployDir, withIntermediateDirectories: true)

            guard fileManager.fileExists(atPath: buildPath) else { throw MoveError.binaryNotFound(buildPath) }
            if fileManager.fileExists(atPath: backupPath) { try fileManager.removeItem(atPath: backupPath) }
            if fileManager.fileExists(atPath: deployPath) { try fileManager.moveItem(atPath: deployPath, toPath: backupPath) }

            do {
                try fileManager.moveItem(atPath: buildPath, toPath: deployPath)
                if fileManager.fileExists(atPath: backupPath) { try? fileManager.removeItem(atPath: backupPath) }
            } catch {
                let moveError = error
                if fileManager.fileExists(atPath: backupPath) {
                    do {
                        if fileManager.fileExists(atPath: deployPath) { try fileManager.removeItem(atPath: deployPath) }
                        try fileManager.moveItem(atPath: backupPath, toPath: deployPath)
                    } catch {
                        throw MoveError.deploymentAndRollbackFailed(moveError.localizedDescription, error.localizedDescription)
                    }
                }

                throw MoveError.deploymentFailed(moveError.localizedDescription)
            }
        }.get()
    }
    
}

extension String {
    
    var shellQuoted: String { "'\(replacingOccurrences(of: "'", with: "'\"'\"'"))'" }
    
}

extension DeployerWorker {
    
    enum MoveError: LocalizedError, CustomStringConvertible, CustomDebugStringConvertible {
        
        case binaryNotFound(String)
        case deploymentFailed(String)
        case deploymentAndRollbackFailed(String, String)

        var errorDescription: String? {
            switch self {
            case .binaryNotFound(let path):
                "New binary not found at '\(path)'."
                
            case .deploymentFailed(let error):
                "Deployment failed: \(error). Rollback successful."
                
            case .deploymentAndRollbackFailed(let error, let rollback):
                "Deployment failed: \(error). Rollback failed: \(rollback)."
            }
        }

        var description: String {
            errorDescription ?? "Deployment move failed."
        }

        var debugDescription: String {
            description
        }
        
    }
    
}
