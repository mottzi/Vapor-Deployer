import Vapor

/// Determines the source or pre-built executable payload and stages it into the final installation directory.
struct StageDeployerStep: SetupStep {

    let context: SetupContext
    let console: any Console

    let title = "Preparing deployer payload"

    func run() async throws {
        
        if context.buildFromSource {
            try await installFromSource()
        } else {
            try await installFromBinary()
        }
    }

}

extension StageDeployerStep {
    
    /// Updates an existing repository clone or creates a fresh one to build the deployer from source.
    private func installFromSource() async throws {
        
        if FileManager.default.fileExists(atPath: "\(paths.installDirectory)/.git") {
            try await shell.git("fetch", ["origin", context.deployerRepositoryBranch, "--prune"], in: paths.installDirectory)
            try await shell.git("checkout", [context.deployerRepositoryBranch], in: paths.installDirectory)
            try await shell.git("pull", ["--ff-only", "origin", context.deployerRepositoryBranch], in: paths.installDirectory)
            
            console.print("Deployer checkout updated.")
        } else {
            if FileManager.default.fileExists(atPath: paths.installDirectory) {
                try? FileManager.default.removeItem(atPath: paths.installDirectory)
            }
            
            try await shell.git("clone", [
                "--branch", context.deployerRepositoryBranch,
                context.deployerRepositoryURL,
                paths.installDirectory
            ])
            
            console.print("Deployer checkout ready.")
        }
    }
    
    /// Acquires and installs a pre-built executable alongside its required web assets.
    private func installFromBinary() async throws {
        
        try await SystemFileSystem.installDirectory(paths.installDirectory, owner: context.serviceUser, group: context.serviceUser)
        
        let currentExecutableURL = try Configuration.getExecutableURL()
        let executableDirectory = currentExecutableURL.deletingLastPathComponent()
        let publicDirectory = executableDirectory.appendingPathComponent("Public", isDirectory: true)
        let resourcesDirectory = executableDirectory.appendingPathComponent("Resources", isDirectory: true)
        let localReleaseTag = DeployerReleaseAssets.localReleaseTag(in: executableDirectory)
        context.releaseVersion = localReleaseTag
        
        if FileManager.default.fileExists(atPath: publicDirectory.path),
           FileManager.default.fileExists(atPath: resourcesDirectory.path) {
            if PathComparison.isSamePath(executableDirectory.path, paths.installDirectory) {
                try await Shell.runThrowing("chmod", ["0755", paths.deployerBinary])
                try await Shell.runThrowing("chown", ["-R", "\(context.serviceUser):\(context.serviceUser)", paths.installDirectory])
                if let localReleaseTag { try await writeReleaseVersion(localReleaseTag) }
                console.print("Current deployer payload is already in the install directory.")
                return
            }
            
            try await installPayload(
                binary: currentExecutableURL.path,
                publicDirectory: publicDirectory.path,
                resourcesDirectory: resourcesDirectory.path,
                versionFile: executableDirectory.appendingPathComponent(".version").path
            )
            if let localReleaseTag { try await writeReleaseVersion(localReleaseTag) }
            console.print("Installed deployer payload from current release directory.")
        } else if let localReleaseTag {
            let stagingPath = try await Shell.runThrowing("mktemp", ["-d"]).trimmed
            defer { try? FileManager.default.removeItem(atPath: stagingPath) }
            
            console.print("Downloading deployer web assets for \(localReleaseTag).")
            let assets = try await DeployerReleaseAssets.downloadSourceAssets(tag: localReleaseTag, into: stagingPath)
            try await installPayload(
                binary: currentExecutableURL.path,
                publicDirectory: assets.publicDirectory,
                resourcesDirectory: assets.resourcesDirectory,
                versionFile: nil
            )
            try await writeReleaseVersion(localReleaseTag)
            console.print("Installed deployer binary with repository assets for \(localReleaseTag).")
        } else {
            try await installLatestRelease()
        }
    }
    
}

extension StageDeployerStep {

    /// Fetches the most recent published release archive from GitHub and stages its contents.
    private func installLatestRelease() async throws {
        
        let (tagName, downloadURL) = try await DeployerReleaseAssets.fetchLatestReleaseMetadata()
        context.releaseVersion = tagName

        let archivePath = try await Shell.runThrowing("mktemp", []).trimmed
        defer { try? FileManager.default.removeItem(atPath: archivePath) }

        let stagingPath = try await Shell.runThrowing("mktemp", ["-d"]).trimmed
        defer { try? FileManager.default.removeItem(atPath: stagingPath) }

        console.print("Downloading \(downloadURL).")
        try await Shell.runThrowing("curl", ["--silent", "--show-error", "--fail", "--location", "-o", archivePath, downloadURL])
        try await Shell.runThrowing("tar", ["-xzf", archivePath, "-C", stagingPath, "--warning=no-unknown-keyword"])
        let assets = try await DeployerReleaseAssets.ensureAssets(in: stagingPath, tag: tagName)

        try await installPayload(
            binary: "\(stagingPath)/deployer",
            publicDirectory: assets.publicDirectory,
            resourcesDirectory: assets.resourcesDirectory,
            versionFile: nil
        )

        try await writeReleaseVersion(tagName)
        console.print("Deployer release \(tagName) installed.")
    }

    /// Copies the executable binary, public directory, and resources into their final destinations.
    private func installPayload(
        binary: String,
        publicDirectory: String,
        resourcesDirectory: String,
        versionFile: String?
    ) async throws {
        
        guard FileManager.default.fileExists(atPath: binary) else {
            throw SystemError.invalidValue("deployer binary", "expected binary missing at '\(binary)'")
        }

        if !PathComparison.isSamePath(binary, paths.deployerBinary) {
            try await Shell.runThrowing("install", ["-m", "0755", "-o", context.serviceUser, "-g", context.serviceUser, binary, paths.deployerBinary])
        }

        if FileManager.default.fileExists(atPath: publicDirectory),
           !PathComparison.isSamePath(publicDirectory, "\(paths.installDirectory)/Public") {
            try SystemFileSystem.copyReplacing(source: publicDirectory, destination: "\(paths.installDirectory)/Public")
        }
        
        if FileManager.default.fileExists(atPath: resourcesDirectory),
           !PathComparison.isSamePath(resourcesDirectory, "\(paths.installDirectory)/Resources") {
            try SystemFileSystem.copyReplacing(source: resourcesDirectory, destination: "\(paths.installDirectory)/Resources")
        }

        if let versionFile,
           FileManager.default.fileExists(atPath: versionFile),
           !PathComparison.isSamePath(versionFile, "\(paths.installDirectory)/.version") {
            try SystemFileSystem.copyReplacing(source: versionFile, destination: "\(paths.installDirectory)/.version")
        }

        try await Shell.runThrowing("chown", [
            "-R", "\(context.serviceUser):\(context.serviceUser)",
            paths.installDirectory
        ])
    }

    /// Records the active release tag into a local tracking file to avoid redundant downloads.
    private func writeReleaseVersion(_ tagName: String) async throws {
        try await SystemFileSystem.writeFile(tagName, to: "\(paths.installDirectory)/.version", owner: context.serviceUser, group: context.serviceUser)
    }
    
}
