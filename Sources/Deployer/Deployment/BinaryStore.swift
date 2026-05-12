import Vapor
import Fluent

struct BinaryStore: Sendable {

    let target: TargetConfiguration

    var deployDirectoryPath: String { "\(target.directory)/deploy" }
    var liveBinaryPath: String { "\(deployDirectoryPath)/\(target.name)" }
    var binariesDirectoryPath: String { "\(deployDirectoryPath)/binaries" }

    func binaryPath(for deployment: Deployment) throws -> String {
        guard let id = deployment.id else { throw Worker.Error.deploymentIDMissing }
        return "\(binariesDirectoryPath)/\(id.uuidString)"
    }

    func hasBinary(for deployment: Deployment) -> Bool {
        guard let path = try? binaryPath(for: deployment) else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    func binarySizeMB(for deployment: Deployment) throws -> Int? {
        guard let path = try? binaryPath(for: deployment) else { return nil }
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return try Self.roundedMegabytes(atPath: path)
    }

    @discardableResult
    func storeBuiltBinary(for deployment: Deployment, app: Application, manually: Bool) async throws -> Int {
        let sourcePath = "\(target.directory)/.build/\(target.buildMode)/\(deployment.product)"
        let destinationPath = try binaryPath(for: deployment)

        let size = try await app.threadPool.runIfActive(eventLoop: app.eventLoopGroup.any()) {
            let fileManager = FileManager.default
            try fileManager.createDirectory(atPath: binariesDirectoryPath, withIntermediateDirectories: true)
            guard fileManager.fileExists(atPath: sourcePath) else { throw Worker.Error.binaryNotFound(sourcePath) }
            guard !fileManager.fileExists(atPath: destinationPath) else { throw Worker.Error.binaryAlreadyExists(destinationPath) }
            try fileManager.moveItem(atPath: sourcePath, toPath: destinationPath)
            return try Self.roundedMegabytes(atPath: destinationPath)
        }.get()

        try await markStored(deployment, sizeMB: size, manually: manually, on: app.db)
        return size
    }

    @discardableResult
    func storeLiveBinary(for deployment: Deployment, app: Application, manually: Bool) async throws -> Int {
        let destinationPath = try binaryPath(for: deployment)

        let size = try await app.threadPool.runIfActive(eventLoop: app.eventLoopGroup.any()) {
            let fileManager = FileManager.default
            try fileManager.createDirectory(atPath: binariesDirectoryPath, withIntermediateDirectories: true)
            guard fileManager.fileExists(atPath: liveBinaryPath) else { throw Worker.Error.binaryNotFound(liveBinaryPath) }
            if fileManager.fileExists(atPath: destinationPath) {
                try fileManager.removeItem(atPath: destinationPath)
            }
            try fileManager.copyItem(atPath: liveBinaryPath, toPath: destinationPath)
            return try Self.roundedMegabytes(atPath: destinationPath)
        }.get()

        try await markStored(deployment, sizeMB: size, manually: manually, on: app.db)
        return size
    }

    func deleteBinary(for deployment: Deployment) throws {
        let path = try binaryPath(for: deployment)
        guard FileManager.default.fileExists(atPath: path) else { return }
        try FileManager.default.removeItem(atPath: path)
    }

    func evict(on database: Database) async throws {
        switch target.binaryBehaviour {
        case .all:
            return
        case .none:
            let candidates = try await automaticCandidates(on: database)
            try await remove(candidates, on: database)
        case .newest(let count):
            let candidates = try await automaticCandidates(on: database)
            let sorted = candidates.sorted { lhs, rhs in
                sortDate(for: lhs) > sortDate(for: rhs)
            }
            guard sorted.count > count else { return }
            try await remove(Array(sorted.dropFirst(count)), on: database)
        case .automatic(let mb):
            var candidates = try await automaticCandidates(on: database)
                .sorted { lhs, rhs in sortDate(for: lhs) < sortDate(for: rhs) }
            var totalBytes = try candidates.reduce(Int64(0)) { total, deployment in
                total + (try binaryByteCount(for: deployment) ?? 0)
            }
            let limitBytes = Int64(mb) * 1_048_576
            var evicted: [Deployment] = []

            while totalBytes > limitBytes, !candidates.isEmpty {
                let deployment = candidates.removeFirst()
                totalBytes -= try binaryByteCount(for: deployment) ?? 0
                evicted.append(deployment)
            }

            try await remove(evicted, on: database)
        }
    }

    func syncMetadata(for deployment: Deployment, on database: Database) async throws {
        let size = try binarySizeMB(for: deployment)
        let shouldClearManualSave = size == nil && deployment.isManuallySaved
        guard deployment.binarySizeMB != size || shouldClearManualSave else { return }

        deployment.binarySizeMB = size
        if size == nil {
            deployment.isManuallySaved = false
        }
        try await deployment.save(on: database)
    }

    func syncMetadata(product: String, on database: Database) async throws {
        let deployments = try await Deployment.query(on: database)
            .filter(\.$product, .equal, product)
            .all()

        for deployment in deployments {
            try await syncMetadata(for: deployment, on: database)
        }
    }

}

extension BinaryStore {

    private func markStored(_ deployment: Deployment, sizeMB: Int, manually: Bool, on database: Database) async throws {
        deployment.binarySizeMB = sizeMB
        deployment.isManuallySaved = deployment.isManuallySaved || manually
        try await deployment.save(on: database)
    }

    private func automaticCandidates(on database: Database) async throws -> [Deployment] {
        let deployments = try await Deployment.query(on: database)
            .filter(\.$product, .equal, target.name)
            .filter(\.$isLive, .equal, false)
            .filter(\.$isManuallySaved, .equal, false)
            .all()

        return deployments.filter { hasBinary(for: $0) }
    }

    private func remove(_ deployments: [Deployment], on database: Database) async throws {
        for deployment in deployments {
            try deleteBinary(for: deployment)
            deployment.binarySizeMB = nil
            deployment.isManuallySaved = false
            try await deployment.save(on: database)
        }
    }

    private func binaryByteCount(for deployment: Deployment) throws -> Int64? {
        guard let path = try? binaryPath(for: deployment) else { return nil }
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        return (attributes[.size] as? NSNumber)?.int64Value
    }

    private func sortDate(for deployment: Deployment) -> Date {
        deployment.finishedAt ?? deployment.startedAt ?? .distantPast
    }

    static func roundedMegabytes(atPath path: String) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        let bytes = (attributes[.size] as? NSNumber)?.doubleValue ?? 0
        return Int((bytes / 1_048_576).rounded())
    }

}

struct DeploymentBinaryCleanupMiddleware: AsyncModelMiddleware {

    typealias Model = Deployment

    let target: TargetConfiguration

    func delete(
        model: Deployment,
        force: Bool,
        on db: any Database,
        next: any AnyAsyncModelResponder
    ) async throws {
        try await next.delete(model, force: force, on: db)
        guard model.product == target.name else { return }
        try BinaryStore(target: target).deleteBinary(for: model)
    }

}
