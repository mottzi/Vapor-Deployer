import Vapor
import Fluent

struct BinaryStore {

    let target: TargetConfiguration

    /// /home/vapor/apps/<name>/deploy
    var deployPath: String { "\(target.directory)/deploy" }
    
    /// /home/vapor/apps/<name>/deploy/binaries
    var binariesPath: String { "\(deployPath)/binaries" }
    
    /// /home/vapor/apps/<name>/deploy/<name>
    var liveBinaryPath: String { "\(deployPath)/\(target.name)" }

    /// /home/vapor/apps/<name>/deploy/binaries/<id>
    func binaryPath(for deployment: Deployment) throws -> String {
        guard let id = deployment.id else { throw Error.deploymentIDMissing }
        return "\(binariesPath)/\(id.uuidString)"
    }

    /// Verifies whether the compiled binary file physically exists on the disk for a given deployment.
    func hasBinary(for deployment: Deployment) -> Bool {
        guard let path = try? binaryPath(for: deployment) else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    /// Calculates the storage footprint of the deployment's binary in rounded megabytes if it exists on disk.
    func binarySizeMB(for deployment: Deployment) throws -> Int? {
        guard let path = try? binaryPath(for: deployment) else { return nil }
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return try Self.roundedMegabytes(atPath: path)
    }

}

extension BinaryStore {

    @discardableResult
    /// Archives the newly compiled binary from the target's build folder into the storage directory.
    func archiveBinary(for deployment: Deployment, app: Application, manually: Bool) async throws -> Int {
        
        let sourcePath = "\(target.directory)/.build/\(target.buildMode)/\(deployment.product)"
        let destinationPath = try binaryPath(for: deployment)

        let size = try await app.threadPool.runIfActive(eventLoop: app.eventLoopGroup.any()) {
            let fileManager = FileManager.default
            try fileManager.createDirectory(atPath: binariesPath, withIntermediateDirectories: true)
            
            guard fileManager.fileExists(atPath: sourcePath) else { throw Error.binaryNotFound(sourcePath) }
            guard !fileManager.fileExists(atPath: destinationPath) else { throw Error.binaryAlreadyExists(destinationPath) }
            
            try fileManager.moveItem(atPath: sourcePath, toPath: destinationPath)
            
            return try Self.roundedMegabytes(atPath: destinationPath)
        }.get()

        try await markStored(deployment, sizeMB: size, manually: manually, on: app.db)
        
        return size
    }

    @discardableResult
    /// Copies the currently running live application binary into the binary store as a backup/rollback point.
    func archiveLiveBinary(for deployment: Deployment, app: Application, manually: Bool) async throws -> Int {
        
        let destinationPath = try binaryPath(for: deployment)

        let size = try await app.threadPool.runIfActive(eventLoop: app.eventLoopGroup.any()) {
            let fileManager = FileManager.default
            try fileManager.createDirectory(atPath: binariesPath, withIntermediateDirectories: true)
            
            guard fileManager.fileExists(atPath: liveBinaryPath) else { throw Error.binaryNotFound(liveBinaryPath) }
            if fileManager.fileExists(atPath: destinationPath) {
                try fileManager.removeItem(atPath: destinationPath)
            }
            
            try fileManager.copyItem(atPath: liveBinaryPath, toPath: destinationPath)
            
            return try Self.roundedMegabytes(atPath: destinationPath)
        }.get()

        try await markStored(deployment, sizeMB: size, manually: manually, on: app.db)
        
        return size
    }

    /// Physically deletes the stored binary file associated with a deployment from the disk.
    func deleteBinary(for deployment: Deployment) throws {
        let path = try binaryPath(for: deployment)
        guard FileManager.default.fileExists(atPath: path) else { return }
        try FileManager.default.removeItem(atPath: path)
    }

}

extension BinaryStore {

    /// Calculates the size of the file at the given path in rounded megabytes.
    static func roundedMegabytes(atPath path: String) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        let bytes = (attributes[.size] as? NSNumber)?.doubleValue ?? 0
        return Int((bytes / 1_000_000).rounded())
    }

}
