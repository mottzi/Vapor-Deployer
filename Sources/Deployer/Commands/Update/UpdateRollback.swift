import Foundation

/// Restores the pre-update installation and verifies the original service can run again.
struct UpdateRollback {

    let context: UpdateContext

    /// Attempts every restoration before reporting the first failure, then restarts only a fully restored installation.
    func run(originalError: Swift.Error) async throws {

        context.application.logger.warning("Rollback initiated due to update failure: \(originalError.localizedDescription)")

        let fileManager = FileManager.default
        let executableURL = context.stagedBinaryURL.deletingPathExtension()

        do {
            let isRunning = await context.serviceManager.isRunning(product: context.serviceName)
            if isRunning { try await context.serviceManager.stop(product: context.serviceName) }

            var restoreError: Swift.Error?
            do {
                try Self.restoreBackupBinary(context: context, fileManager: fileManager, executableURL: executableURL)
            } catch {
                restoreError = error
            }

            do {
                if let assetBackup = context.assetBackup {
                    try restoreReleaseAssets(
                        from: assetBackup,
                        installDirectory: executableURL.deletingLastPathComponent(),
                        fileManager: fileManager
                    )
                }
            } catch {
                restoreError = restoreError ?? error
            }

            do {
                try restoreVersionMarkerIfNeeded(fileManager: fileManager)
            } catch {
                restoreError = restoreError ?? error
            }

            if let restoreError { throw restoreError }

            try await context.serviceManager.start(product: context.serviceName)

            let rollbackStatus = await context.serviceManager.waitForStableStatus(product: context.serviceName)
            guard rollbackStatus.isRunning else {
                throw UpdateCommand.Error.rollbackVerificationFailed(rollbackStatus.label)
            }
        } catch {
            throw UpdateCommand.Error.rollbackFailed(originalError.localizedDescription, error.localizedDescription)
        }

        throw UpdateCommand.Error.rollbackSucceeded(originalError.localizedDescription)
    }

}

extension UpdateRollback {

    /// Reinstates the last known-good executable after a failed update attempt.
    static func restoreBackupBinary(context: UpdateContext, fileManager: FileManager, executableURL: URL) throws {
        let backupBinaryExists = fileManager.fileExists(atPath: context.backupBinaryURL.path)
        guard backupBinaryExists else {
            throw UpdateCommand.Error.binaryNotFound(context.backupBinaryURL.path)
        }

        try Host.FileSystem.removeIfPresent(executableURL.path)
        try fileManager.moveItem(at: context.backupBinaryURL, to: executableURL)
    }

    /// Restores asset directories to the exact pre-update state captured before activation.
    private func restoreReleaseAssets(
        from backup: UpdateAssetBackup,
        installDirectory: URL,
        fileManager: FileManager
    ) throws {
        for name in UpdateAssetBackup.directoryNames {
            let destination = installDirectory.appendingPathComponent(name, isDirectory: true)
            try Host.FileSystem.removeIfPresent(destination.path)

            guard let source = backup.directory(named: name) else { continue }
            try fileManager.copyItem(at: source, to: destination)
        }
    }

    /// Restores or removes the version marker so it matches the pre-update installation.
    private func restoreVersionMarkerIfNeeded(fileManager: FileManager) throws {
        guard context.versionMarkerAdvanced else { return }

        if context.previousVersionFileExisted {
            guard let data = context.previousVersionFileData else {
                throw UpdateCommand.Error.versionMarkerRollbackFailed(
                    context.versionFileURL.path,
                    "previous marker contents were not captured"
                )
            }

            do {
                try data.write(to: context.versionFileURL, options: .atomic)
            } catch {
                throw UpdateCommand.Error.versionMarkerRollbackFailed(
                    context.versionFileURL.path,
                    error.localizedDescription
                )
            }

            return
        }

        do {
            if fileManager.fileExists(atPath: context.versionFileURL.path) {
                try fileManager.removeItem(at: context.versionFileURL)
            }
        } catch {
            throw UpdateCommand.Error.versionMarkerRollbackFailed(
                context.versionFileURL.path,
                error.localizedDescription
            )
        }
    }

}
