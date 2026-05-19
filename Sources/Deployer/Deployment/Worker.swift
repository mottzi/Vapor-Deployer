import Vapor

struct Worker: Sendable {
    
    let deployment: Deployment
    let target: TargetConfiguration
    let app: Application
    let stream: BuildOutputStream?
    let onStatusChange: @Sendable (ServiceStatus) async -> Void
    
}

extension Worker {

    func checkout() async throws {
        await stream?.appendLabel("git fetch origin \(deployment.branch)")
        try await Shell.runStreaming(
            "git", ["fetch", "origin", deployment.branch],
            directory: target.directory,
            onOutput: { chunk in await stream?.append(chunk) }
        )

        await stream?.appendLabel("git checkout --detach -f \(deployment.commitID.prefix(7))")
        try await Shell.runStreaming(
            "git", ["checkout", "--detach", "-f", deployment.commitID],
            directory: target.directory,
            onOutput: { chunk in await stream?.append(chunk) }
        )
    }

    @discardableResult
    func build() async throws -> String {
        await stream?.appendLabel("swift build -c \(target.buildMode)")
        return try await Shell.runStreaming(
            "swift", ["build", "-c", target.buildMode],
            directory: target.directory,
            onOutput: { chunk in await stream?.append(chunk) }
        )
    }

    @discardableResult
    func test() async throws -> String {
        // Isolated `.build-tests` scratch path so `-enable-testing` artifacts from `swift test`
        // never overwrite the production `.build/` cache used by `swift build`. Without this,
        // alternating between the two commands clobbers each other's object files and forces a
        // full rebuild every push (SwiftPM bug #8031). Costs ~doubled disk usage per target;
        // restores ~20s incremental builds. Matches SwiftPM's own CI pattern.
        await stream?.appendLabel("swift test -c \(target.buildMode) --scratch-path .build-tests")
        return try await Shell.runStreaming(
            "swift", ["test", "-c", target.buildMode, "--scratch-path", ".build-tests"],
            directory: target.directory,
            onOutput: { chunk in await stream?.append(chunk) }
        )
    }

    func restart() async throws {
        let manager = app.deployer.serviceManager
        let status = await manager.status(product: deployment.product)
        await onStatusChange(status.isRunning ? .stopping : .starting)

        try await manager.restart(product: deployment.product)
        await onStatusChange(.starting)

        let finalStatus = await manager.status(product: deployment.product)
        await onStatusChange(finalStatus)
        await stream?.append("Restart service.\n")
    }

    func move() async throws {
        await stream?.appendLabel("deployer")
        await stream?.append("Install binary\n")

        let buildPath = "\(target.directory)/.build/\(target.buildMode)/\(deployment.product)"
        let deployPath = "\(target.directory)/deploy/\(deployment.product)"
        try await replaceLiveBinary(from: buildPath, to: deployPath, transfer: .move)
    }

    func restore(from store: BinaryStore) async throws {
        let binaryPath = try store.binaryPath(for: deployment)
        try await replaceLiveBinary(from: binaryPath, to: store.liveBinaryPath, transfer: .copy)
    }

    func save(to store: BinaryStore) async throws {
        await stream?.appendLabel("deployer")
        try await store.storeBuiltBinary(for: deployment, app: app, manually: true)
        await stream?.append("Archive binary\n")
    }

    func deploy(to store: BinaryStore) async throws {
        try await store.storeLiveBinary(for: deployment, app: app, manually: false)
        await stream?.append("Archive binary\n")
    }

}

extension Worker {

    private enum BinaryTransfer: Sendable {
        case copy
        case move
    }

    /// Atomically swaps the live binary at `deployPath` with the source, keeping a `.old` backup for rollback on failure.
    private func replaceLiveBinary(from sourcePath: String, to deployPath: String, transfer: BinaryTransfer) async throws {

        let eventLoop = app.eventLoopGroup.any()
        let threadPool = app.threadPool

        let deployDir = URL(fileURLWithPath: deployPath).deletingLastPathComponent().path
        let backupPath = "\(deployDir)/\(deployment.product).old"

        try await threadPool.runIfActive(eventLoop: eventLoop) {
            let fileManager = FileManager.default
            try fileManager.createDirectory(atPath: deployDir, withIntermediateDirectories: true)

            guard fileManager.fileExists(atPath: sourcePath) else {
                throw Error.binaryNotFound(sourcePath)
            }
            if fileManager.fileExists(atPath: backupPath) {
                try fileManager.removeItem(atPath: backupPath)
            }
            if fileManager.fileExists(atPath: deployPath) {
                try fileManager.moveItem(atPath: deployPath, toPath: backupPath)
            }

            do {
                switch transfer {
                    case .copy: try fileManager.copyItem(atPath: sourcePath, toPath: deployPath)
                    case .move: try fileManager.moveItem(atPath: sourcePath, toPath: deployPath)
                }
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
                        throw Error.deploymentAndRollbackFailed(moveError.localizedDescription, error.localizedDescription)
                    }
                }

                throw Error.deploymentFailed(moveError.localizedDescription)
            }
        }.get()
    }

}
