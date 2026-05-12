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

    @discardableResult
    /// Runs `swift build` and debounces its output to all connected clients using Mist streams.
    func build(streamingTo relay: MistStreamRelay) async throws -> String {

        try await Shell.runStreaming(
            "swift", ["build", "-c", target.buildMode],
            directory: target.directory,
            onOutput: { chunk in
                await relay.append(chunk)
            }
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
    }

    func move() async throws {
        let buildPath = "\(target.directory)/.build/\(target.buildMode)/\(deployment.product)"
        let deployPath = "\(target.directory)/deploy/\(deployment.product)"
        try await replaceLiveBinary(from: buildPath, to: deployPath, transfer: .move)
    }

    func restore(from store: BinaryStore) async throws {
        let binaryPath = try store.binaryPath(for: deployment)
        try await replaceLiveBinary(from: binaryPath, to: store.liveBinaryPath, transfer: .copy)
    }

}

extension Worker {

    private enum BinaryTransfer: Sendable {
        case copy
        case move
    }

    private func replaceLiveBinary(from sourcePath: String, to deployPath: String, transfer: BinaryTransfer) async throws {

        let eventLoop = app.eventLoopGroup.any()
        let threadPool = app.threadPool

        let deployDir = URL(fileURLWithPath: deployPath).deletingLastPathComponent().path
        let backupPath = "\(deployDir)/\(deployment.product).old"

        try await threadPool.runIfActive(eventLoop: eventLoop) {
            let fileManager = FileManager.default
            try fileManager.createDirectory(atPath: deployDir, withIntermediateDirectories: true)

            guard fileManager.fileExists(atPath: sourcePath) else { throw Error.binaryNotFound(sourcePath) }
            if fileManager.fileExists(atPath: backupPath) { try fileManager.removeItem(atPath: backupPath) }
            if fileManager.fileExists(atPath: deployPath) { try fileManager.moveItem(atPath: deployPath, toPath: backupPath) }

            do {
                switch transfer {
                case .copy:
                    try fileManager.copyItem(atPath: sourcePath, toPath: deployPath)
                case .move:
                    try fileManager.moveItem(atPath: sourcePath, toPath: deployPath)
                }
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

/// Debounces and relays output to conntected clients through Mist streams using time and data size thresholds.
actor MistStreamRelay {

    private static let streamName = "build-output"
    private static let flushInterval: Duration = .milliseconds(100)
    private static let flushByteThreshold = 8 * 1024

    private let app: Application
    private let component: String
    private let modelID: UUID?

    private var pending = ""
    private var flushTask: Task<Void, Never>?

    init(app: Application, deployment: Deployment) {
        self.app = app
        self.component = RowComponent.name(for: deployment.product)
        self.modelID = deployment.id
    }

    /// Resets the stream by clearing any cached output from previous builds of this deployment.
    func start() async {
        
        guard let modelID else { return }
        
        await app.mist.streams.replace(
            component: component,
            modelID: modelID,
            stream: Self.streamName,
            text: ""
        )
    }

    /// Accumulates and streams text to connected clients once the size threshold is reached or the time interval expires.
    func append(_ text: String) async {
        
        guard !text.isEmpty else { return }
        pending.append(text)

        if pending.utf8.count >= Self.flushByteThreshold {
            await flush()
        } else {
            scheduleFlush()
        }
    }

    /// Streams the accumulated text to all connected clients and resets pending debounce timers.
    func flush() async {
        
        flushTask?.cancel()
        flushTask = nil

        guard !pending.isEmpty else { return }
        guard let modelID else { return }
        
        let chunk = pending
        pending = ""

        await app.mist.streams.append(
            component: component,
            modelID: modelID,
            stream: Self.streamName,
            text: chunk
        )
    }

    /// Streams remaining text and closes the Mist stream once the build has ended.
    func close() async {
        
        await flush()
        
        guard let modelID else { return }
        
        await app.mist.streams.close(
            component: component,
            modelID: modelID,
            stream: Self.streamName
        )
    }

    /// Ensures exactly one delayed flush is scheduled at a time.
    private func scheduleFlush() {
        
        guard flushTask == nil else { return }

        flushTask = Task {
            try? await Task.sleep(for: Self.flushInterval)
            await self.flush()
        }
    }

}
