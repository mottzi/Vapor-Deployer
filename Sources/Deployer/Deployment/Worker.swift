import Vapor

struct Worker: Sendable {
    
    let deployment: Deployment
    let target: TargetConfiguration
    let app: Application
    let onStatusChange: @Sendable (ServiceStatus) async -> Void
    
}

extension Worker {
    
    func checkout() async throws {
        try await Shell.runThrowing("git fetch origin \(deployment.branch.shellQuoted)", directory: target.directory)
        try await Shell.runThrowing("git checkout --detach \(deployment.commitID.shellQuoted)", directory: target.directory)
    }

    func build() async throws {
        try await Shell.runThrowing("swift build -c \(target.buildMode)", directory: target.directory)
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

            guard fileManager.fileExists(atPath: buildPath) else { throw Error.binaryNotFound(buildPath) }
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
                        throw Error.deploymentAndRollbackFailed(moveError.localizedDescription, error.localizedDescription)
                    }
                }

                throw Error.deploymentFailed(moveError.localizedDescription)
            }
        }.get()
    }
    
}
