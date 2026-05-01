import Vapor

/// Updates source installs by pulling latest code and building a fresh release binary.
struct SourceUpdateStep: UpdateStep {

    let context: UpdateContext
    let console: any Console

    let title = "Updating from source"

    func run() async throws {
        guard context.isSourceInstall else { return }

        let serviceUser = context.serviceUser.trimmed
        let installDirectory = context.stagedBinaryURL.deletingLastPathComponent().path

        guard !serviceUser.isEmpty else {
            throw SystemError.invalidValue("serviceUser", "unable to determine user for source-based update")
        }

        context.currentVersion = readInstalledVersion(at: context.versionFileURL)
        context.assetBackup = try await backupInstalledAssets()

        console.print("Pulling latest source code from deployer repository.")
        try await SystemShell.runAs(
            user: serviceUser,
            "git",
            ["fetch", "origin", context.deployerBranch],
            directory: installDirectory,
            environment: sourceBuildEnvironment(for: serviceUser)
        )

        let outputBeforeReset = try await SystemShell.runAs(
            user: serviceUser,
            "git",
            ["rev-parse", "HEAD"],
            directory: installDirectory,
            environment: sourceBuildEnvironment(for: serviceUser)
        ).trimmed

        try await SystemShell.runAs(
            user: serviceUser,
            "git",
            ["reset", "--hard", "origin/\(context.deployerBranch)"],
            directory: installDirectory,
            environment: sourceBuildEnvironment(for: serviceUser)
        )

        let outputAfterReset = try await SystemShell.runAs(
            user: serviceUser,
            "git",
            ["rev-parse", "HEAD"],
            directory: installDirectory,
            environment: sourceBuildEnvironment(for: serviceUser)
        ).trimmed

        if outputBeforeReset == outputAfterReset {
            context.releaseVersion = context.currentVersion
            context.isUpToDate = true
            console.print("Source code is already up to date.")
            return
        }

        console.print("Building deployer from source code.")
        _ = try await SystemShell.runAsStreamingTail(
            user: serviceUser,
            "swift",
            ["build", "-c", "release"],
            directory: installDirectory,
            environment: sourceBuildEnvironment(for: serviceUser)
        )

        let binPath = try await SystemShell.runAs(
            user: serviceUser,
            "swift",
            ["build", "-c", "release", "--show-bin-path"],
            directory: installDirectory,
            environment: sourceBuildEnvironment(for: serviceUser)
        ).trimmed

        let executableName = context.stagedBinaryURL.deletingPathExtension().lastPathComponent
        let builtBinaryURL = URL(fileURLWithPath: binPath, isDirectory: true).appendingPathComponent(executableName)
        guard FileManager.default.fileExists(atPath: builtBinaryURL.path) else {
            throw UpdateCommand.Error.binaryNotFound(builtBinaryURL.path)
        }

        try SystemFileSystem.removeIfPresent(context.stagedBinaryURL.path)
        try FileManager.default.copyItem(at: builtBinaryURL, to: context.stagedBinaryURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: context.stagedBinaryURL.path
        )

        context.releaseVersion = try await resolveHeadRevision(serviceUser: serviceUser, directory: installDirectory)
    }

}

extension SourceUpdateStep {

    private func readInstalledVersion(at url: URL) -> String? {
        ConfigDiscovery.readTrimmedTextFile(at: url)
    }

    private func sourceBuildEnvironment(for serviceUser: String) -> [String: String] {
        [
            "HOME": "/home/\(serviceUser)",
            "USER": serviceUser,
            "PATH": "/home/\(serviceUser)/.local/share/swiftly/bin:/usr/local/bin:/usr/bin:/bin"
        ]
    }

    private func resolveHeadRevision(serviceUser: String, directory: String) async throws -> String {
        let revision = try await SystemShell.runAs(
            user: serviceUser,
            "git",
            ["rev-parse", "--short", "HEAD"],
            directory: directory,
            environment: sourceBuildEnvironment(for: serviceUser)
        ).trimmed
        return "source-\(revision)"
    }

    /// Copies installed assets into a temp backup so rollback can restore source updates.
    private func backupInstalledAssets() async throws -> ReleaseAssetBackup {
        let fileManager = FileManager.default
        let backupRootPath = try await Shell.runThrowing("mktemp", ["-d"]).trimmed
        let backupRoot = URL(fileURLWithPath: backupRootPath, isDirectory: true)
            .appendingPathComponent("deployer-assets-backup-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: backupRoot, withIntermediateDirectories: true)

        let installDirectory = context.stagedBinaryURL.deletingLastPathComponent()
        var backedUpDirectoryNames = Set<String>()
        for name in ReleaseAssetBackup.directoryNames {
            let source = installDirectory.appendingPathComponent(name, isDirectory: true)
            guard fileManager.fileExists(atPath: source.path) else { continue }

            let destination = backupRoot.appendingPathComponent(name, isDirectory: true)
            try fileManager.copyItem(at: source, to: destination)
            backedUpDirectoryNames.insert(name)
        }

        return ReleaseAssetBackup(root: backupRoot, backedUpDirectoryNames: backedUpDirectoryNames)
    }

}
