import Vapor

/// Performs an in-place update of the deployed installation.
struct UpdateCommand: AsyncCommand {

    struct Signature: CommandSignature {}

    var help: String { "Updates the deployer installation." }

    /// Updates the live install by building first, then doing a stop / swap / start with rollback on failure.
    func run(using context: CommandContext, signature: Signature) async throws {
        
        let console = context.console

        let paths = try Paths.resolve()
        let config = try Configuration.load()
        let manager = config.serviceManager.makeManager()

        console.print("Preparing deployer update in '\(paths.installDirectory.path)'.")
        try await ensureCleanWorktree(at: paths.installDirectory.path)
        let previousCommitID = try await currentCommitID(in: paths.installDirectory.path)

        console.print("Pulling latest changes.")
        try await Shell.execute("git pull --ff-only", directory: paths.installDirectory.path)

        let currentCommitID = try await currentCommitID(in: paths.installDirectory.path)
        guard currentCommitID != previousCommitID else {
            console.print("Deployer is already up to date.")
            return
        }

        console.print("Building updated deployer binary.")
        do {
            try await Shell.execute("swift build -c \(paths.buildMode)", directory: paths.installDirectory.path)
        } catch let error as Shell.Error {
            let output = error.output.trimmed
            if !output.isEmpty { console.print(.init(stringLiteral: output)) }
            throw Error.buildFailed(paths.buildMode)
        }
        
        try stageCandidateBinary(using: paths)

        console.print("Stopping service '\(paths.serviceName)'.")
        let wasRunning = await manager.isRunning(product: paths.serviceName)
        if wasRunning { try await manager.stop(product: paths.serviceName) }

        do {
            try activateCandidateBinary(using: paths)

            console.print("Starting service '\(paths.serviceName)'.")
            try await manager.start(product: paths.serviceName)

            let finalStatus = await waitForStableStatus(of: paths.serviceName, manager: manager)
            guard finalStatus.isRunning else { throw Error.restartVerificationFailed(finalStatus.label) }

            console.print("Deployer update completed successfully.")
        } catch {
            console.print("Update failed after service stop. Attempting rollback.")
            try await rollback(using: paths, manager: manager, originalError: error)
        }
    }
    
}

extension UpdateCommand {
    
    /// Rejects dirty server checkouts so the update command never discards uncommitted operational changes.
    func ensureCleanWorktree(at directory: String) async throws {
        
        let gitDirectory = URL(fileURLWithPath: directory, isDirectory: true).appendingPathComponent(".git")
        let gitDirectoryExists = FileManager.default.fileExists(atPath: gitDirectory.path)
        guard gitDirectoryExists else { throw Error.notGitRepository(directory) }
        
        let command = "git status --porcelain --untracked-files=no"
        let status = await Shell.executeResult(command, directory: directory)
        guard status.exitCode == 0 else { throw Shell.Error(command: command, output: status.output) }
        
        let trimmedStatus = status.output.trimmed
        guard trimmedStatus.isEmpty else { throw Error.dirtyWorktree(trimmedStatus) }
    }
    
    /// Reads the current checkout commit so the command can skip the restart path when no new revision arrived.
    func currentCommitID(in directory: String) async throws -> String {
        
        let commitID = try await Shell.execute("git rev-parse HEAD", directory: directory)
        let trimmedCommitID = commitID.trimmed
        guard !trimmedCommitID.isEmpty else { throw Error.emptyCommitID }
        
        return trimmedCommitID
    }
    
    /// Stages the freshly built binary beside the live one so cutover only happens after a successful build.
    func stageCandidateBinary(using paths: Paths) throws {
        
        let fileManager = FileManager.default
        
        let fileExists = fileManager.fileExists(atPath: paths.buildOutputURL.path)
        guard fileExists else { throw Error.binaryNotFound(paths.buildOutputURL.path) }
        
        try removeIfPresent(paths.stagedBinaryURL, fileManager: fileManager)
        try fileManager.copyItem(at: paths.buildOutputURL, to: paths.stagedBinaryURL)
        try fileManager.setAttributes([.posixPermissions: NSNumber(value: Int16(0o755))], ofItemAtPath: paths.stagedBinaryURL.path)
    }
    
    /// Swaps the staged binary into place with a same-directory rename and preserves a rollback copy.
    func activateCandidateBinary(using paths: Paths) throws {
        
        let fileManager = FileManager.default
        
        try removeIfPresent(paths.backupBinaryURL, fileManager: fileManager)
        
        let liveBinaryExists = fileManager.fileExists(atPath: paths.executableURL.path)
        guard liveBinaryExists else { throw Error.binaryNotFound(paths.executableURL.path) }
        
        let stagedBinaryExists = fileManager.fileExists(atPath: paths.stagedBinaryURL.path)
        guard stagedBinaryExists else { throw Error.binaryNotFound(paths.stagedBinaryURL.path) }
        
        try fileManager.moveItem(at: paths.executableURL, to: paths.backupBinaryURL)
        
        do {
            try fileManager.moveItem(at: paths.stagedBinaryURL, to: paths.executableURL)
        } catch {
            try? restoreBackup(using: paths, fileManager: fileManager)
            throw Error.binarySwapFailed(error.localizedDescription)
        }
    }
    
    /// Restores the last known-good binary and requires the service manager to recover before declaring rollback success.
    func rollback(using paths: Paths, manager: any ServiceManager, originalError: Swift.Error) async throws {
        
        let fileManager = FileManager.default
        
        do {
            let isRunning = await manager.isRunning(product: paths.serviceName)
            if isRunning { try await manager.stop(product: paths.serviceName) }
            
            try restoreBackup(using: paths, fileManager: fileManager)
            try await manager.start(product: paths.serviceName)
            
            let rollbackStatus = await waitForStableStatus(of: paths.serviceName, manager: manager)
            guard rollbackStatus.isRunning else { throw Error.rollbackVerificationFailed(rollbackStatus.label) }
        } catch {
            throw Error.rollbackFailed(originalError.localizedDescription, error.localizedDescription)
        }
        
        throw Error.rollbackSucceeded(originalError.localizedDescription)
    }
    
    /// Waits through transient service states so the command judges the final service state instead of a race.
    func waitForStableStatus(of serviceName: String, manager: any ServiceManager) async -> ServiceStatus {
        
        for _ in 0..<10 {
            let status = await manager.status(product: serviceName)
            let isStableStatus = status.isRunning || !status.isTransitioning
            if isStableStatus { return status }
            
            try? await Task.sleep(for: .milliseconds(500))
        }
        
        return await manager.status(product: serviceName)
    }
    
    /// Reinstates the last known-good executable after a failed update attempt.
    func restoreBackup(using paths: Paths, fileManager: FileManager) throws {
        
        let backupBinaryExists = fileManager.fileExists(atPath: paths.backupBinaryURL.path)
        guard backupBinaryExists else { throw Error.binaryNotFound(paths.backupBinaryURL.path) }
        
        try removeIfPresent(paths.executableURL, fileManager: fileManager)
        try fileManager.moveItem(at: paths.backupBinaryURL, to: paths.executableURL)
    }
    
    /// Removes stale artifacts from earlier attempts so each update starts from a predictable filesystem state.
    func removeIfPresent(_ url: URL, fileManager: FileManager) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }
    
}

extension UpdateCommand {
    
    /// Captures install-local paths so the command always targets the launched deployer installation.
    struct Paths: Sendable {
        
        let executableURL: URL
        let installDirectory: URL
        let buildOutputURL: URL
        let stagedBinaryURL: URL
        let backupBinaryURL: URL
        let serviceName: String
        let buildMode: String
        
        /// Resolves update paths from the launched executable rather than the caller's current working directory.
        static func resolve(
            executableURL: URL? = nil,
            buildMode: String = "release",
            serviceName: String = "deployer"
        ) throws -> Paths {
            
            let executableURL = try executableURL ?? Configuration.getExecutableURL()
            let resolvedExecutableURL = executableURL.standardizedFileURL.resolvingSymlinksInPath()
            let installDirectory = resolvedExecutableURL.deletingLastPathComponent()
            let executableName = resolvedExecutableURL.lastPathComponent
            
            guard !executableName.isEmpty else { throw Error.invalidExecutablePath(resolvedExecutableURL.path) }
            
            return Paths(
                executableURL: resolvedExecutableURL,
                installDirectory: installDirectory,
                buildOutputURL: installDirectory
                    .appendingPathComponent(".build", isDirectory: true)
                    .appendingPathComponent(buildMode, isDirectory: true)
                    .appendingPathComponent(executableName, isDirectory: false),
                stagedBinaryURL: installDirectory.appendingPathComponent("\(executableName).new", isDirectory: false),
                backupBinaryURL: installDirectory.appendingPathComponent("\(executableName).old", isDirectory: false),
                serviceName: serviceName,
                buildMode: buildMode
            )
        }
        
    }
    
}
