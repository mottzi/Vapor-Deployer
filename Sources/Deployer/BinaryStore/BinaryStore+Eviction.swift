import Vapor
import Fluent

extension BinaryStore {
    
    /// Enforces target-specific retention policies by evicting older stored binaries from disk and updating database records.
    func evict(on database: Database) async throws {
        switch target.binaryBehaviour {
            case .all: return
            case .off: try await evictOff(on: database)
            case .newest(let count): try await evictNewest(count, on: database)
            case .automatic(let mb): try await evictAutomatic(limitMB: mb, on: database)
        }
    }
    
}

extension BinaryStore {
    
    /// Purges all cached binaries that are not actively running or flagged for manual preservation.
    private func evictOff(on database: Database) async throws {
        let candidates = try await automaticCandidates(on: database)
        try await remove(candidates, on: database)
    }
    
    /// Retains only the specified number of most recently completed builds, purging older ones.
    private func evictNewest(_ count: Int, on database: Database) async throws {
        
        let candidates = try await automaticCandidates(on: database)
        
        let sorted = candidates.sorted { lhs, rhs in
            sortDate(for: lhs) > sortDate(for: rhs)
        }
        guard sorted.count > count else { return }
        
        try await remove(Array(sorted.dropFirst(count)), on: database)
    }
    
    /// Enforces a disk space budget by purging the oldest builds until candidate storage falls below the megabyte limit.
    private func evictAutomatic(limitMB mb: Int, on database: Database) async throws {
        
        var candidates = try await automaticCandidates(on: database)
            .sorted { lhs, rhs in sortDate(for: lhs) < sortDate(for: rhs) }
        
        var totalBytes = try candidates.reduce(Int64(0)) { total, deployment in
            total + (try binaryByteCount(for: deployment) ?? 0)
        }
        
        let limitBytes = Int64(mb) * 1_000_000
        var evicted: [Deployment] = []
        
        while totalBytes > limitBytes, !candidates.isEmpty {
            let deployment = candidates.removeFirst()
            totalBytes -= try binaryByteCount(for: deployment) ?? 0
            evicted.append(deployment)
        }
        
        try await remove(evicted, on: database)
    }
    
}

extension BinaryStore {

    /// Retrieves deployments that possess stored binaries and are eligible for automatic eviction policies.
    private func automaticCandidates(on database: Database) async throws -> [Deployment] {
        
        let deployments = try await Deployment.query(on: database)
            .filter(\.$product, .equal, target.name)
            .filter(\.$isLive, .equal, false)
            .filter(\.$isManuallySaved, .equal, false)
            .all()

        return deployments.filter { hasBinary(for: $0) }
    }

    /// Deletes the binaries of the specified deployments from disk and resets their database storage properties.
    private func remove(_ deployments: [Deployment], on database: Database) async throws {
        
        for deployment in deployments {
            
            try deleteBinary(for: deployment)
            database.logger.info("Evicted binary for commit \(deployment.commitID.prefix(7)) due to storage limits")

            deployment.binarySizeMB = nil
            deployment.isManuallySaved = false
            
            try await deployment.save(on: database)
        }
    }

    /// Establishes the chronological priority of a deployment for retention and eviction sorting.
    private func sortDate(for deployment: Deployment) -> Date {
        deployment.finishedAt ?? deployment.startedAt ?? .distantPast
    }
    
    /// Resolves the raw file size in bytes for a deployment's stored binary.
    private func binaryByteCount(for deployment: Deployment) throws -> Int64? {
        
        guard let path = try? binaryPath(for: deployment) else { return nil }
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        return (attributes[.size] as? NSNumber)?.int64Value
    }

}
