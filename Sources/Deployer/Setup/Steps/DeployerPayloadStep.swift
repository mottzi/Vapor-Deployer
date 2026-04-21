import Vapor
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct DeployerPayloadStep: SetupStep {

    let context: SetupContext
    let console: any Console

    let title = "Preparing deployer payload"

    func run() async throws {
        
        if context.buildFromSource {
            try await prepareSourceCheckout()
        } else {
            try await prepareBinaryPayload()
        }
    }

}

extension DeployerPayloadStep {
    
    private func prepareSourceCheckout() async throws {
        
        let paths = try context.requirePaths()
        
        if FileManager.default.fileExists(atPath: "\(paths.installDirectory)/.git") {
            try await shell.runAsServiceUser("git", ["-C", paths.installDirectory, "fetch", "origin", context.deployerRepositoryBranch, "--prune"])
            try await shell.runAsServiceUser("git", ["-C", paths.installDirectory, "checkout", context.deployerRepositoryBranch])
            try await shell.runAsServiceUser("git", ["-C", paths.installDirectory, "pull", "--ff-only", "origin", context.deployerRepositoryBranch])
            console.print("Deployer checkout updated.")
        } else {
            if FileManager.default.fileExists(atPath: paths.installDirectory) {
                try? FileManager.default.removeItem(atPath: paths.installDirectory)
            }
            try await shell.runAsServiceUser("git clone", [
                "--branch", context.deployerRepositoryBranch,
                context.deployerRepositoryURL,
                paths.installDirectory
            ])
            console.print("Deployer checkout ready.")
        }
    }
    
    private func prepareBinaryPayload() async throws {
        let paths = try context.requirePaths()
        try await SetupFileSystem.installDirectory(paths.installDirectory, owner: context.serviceUser, group: context.serviceUser)
        
        let executableURL = try Configuration.getExecutableURL()
        let sourceDirectory = executableURL.deletingLastPathComponent()
        let publicDirectory = sourceDirectory.appendingPathComponent("Public", isDirectory: true)
        let resourcesDirectory = sourceDirectory.appendingPathComponent("Resources", isDirectory: true)
        let localReleaseTag = DeployerReleaseAssets.localReleaseTag(in: sourceDirectory)
        context.releaseVersion = localReleaseTag
        
        if FileManager.default.fileExists(atPath: publicDirectory.path),
           FileManager.default.fileExists(atPath: resourcesDirectory.path) {
            if sourceDirectory.standardizedFileURL.path == URL(fileURLWithPath: paths.installDirectory, isDirectory: true).standardizedFileURL.path {
                try await Shell.runThrowing("chmod", ["0755", paths.deployerBinary])
                try await Shell.runThrowing("chown", ["-R", "\(context.serviceUser):\(context.serviceUser)", paths.installDirectory])
                if let localReleaseTag {
                    try await writeReleaseVersion(localReleaseTag)
                }
                console.print("Current deployer payload is already in the install directory.")
                return
            }
            
            try await installPayload(
                binary: executableURL.path,
                publicDirectory: publicDirectory.path,
                resourcesDirectory: resourcesDirectory.path,
                versionFile: sourceDirectory.appendingPathComponent(".version").path
            )
            if let localReleaseTag {
                try await writeReleaseVersion(localReleaseTag)
            }
            console.print("Installed deployer payload from current release directory.")
        } else if let localReleaseTag {
            let staging = try await Shell.runThrowing("mktemp", ["-d"]).trimmed
            defer { try? FileManager.default.removeItem(atPath: staging) }
            
            console.print("Downloading deployer web assets for \(localReleaseTag).")
            let assets = try await DeployerReleaseAssets.downloadSourceAssets(tag: localReleaseTag, into: staging)
            try await installPayload(
                binary: executableURL.path,
                publicDirectory: assets.publicDirectory,
                resourcesDirectory: assets.resourcesDirectory,
                versionFile: nil
            )
            try await writeReleaseVersion(localReleaseTag)
            console.print("Installed deployer binary with repository assets for \(localReleaseTag).")
        } else {
            try await downloadAndInstallLatestRelease()
        }
    }
    
}

extension DeployerPayloadStep {

    private func downloadAndInstallLatestRelease() async throws {
        let (tagName, downloadURL) = try await fetchLatestRelease()
        context.releaseVersion = tagName

        let archive = try await Shell.runThrowing("mktemp", []).trimmed
        defer { try? FileManager.default.removeItem(atPath: archive) }

        let staging = try await Shell.runThrowing("mktemp", ["-d"]).trimmed
        defer { try? FileManager.default.removeItem(atPath: staging) }

        console.print("Downloading \(downloadURL).")
        try await Shell.runThrowing("curl", ["--silent", "--show-error", "--fail", "--location", "-o", archive, downloadURL])
        try await Shell.runThrowing("tar", ["-xzf", archive, "-C", staging, "--warning=no-unknown-keyword"])
        let assets = try await DeployerReleaseAssets.ensureAssets(in: staging, tag: tagName)

        try await installPayload(
            binary: "\(staging)/deployer",
            publicDirectory: assets.publicDirectory,
            resourcesDirectory: assets.resourcesDirectory,
            versionFile: nil
        )

        try await writeReleaseVersion(tagName)
        console.print("Deployer release \(tagName) installed.")
    }

    private func installPayload(
        binary: String,
        publicDirectory: String,
        resourcesDirectory: String,
        versionFile: String?
    ) async throws {

        let paths = try context.requirePaths()
        guard FileManager.default.fileExists(atPath: binary) else {
            throw SetupCommand.Error.invalidValue("deployer binary", "expected binary missing at '\(binary)'")
        }

        if URL(fileURLWithPath: binary).standardizedFileURL.path != URL(fileURLWithPath: paths.deployerBinary).standardizedFileURL.path {
            try await Shell.runThrowing("install", ["-m", "0755", "-o", context.serviceUser, "-g", context.serviceUser, binary, paths.deployerBinary])
        }

        if FileManager.default.fileExists(atPath: publicDirectory),
           URL(fileURLWithPath: publicDirectory).standardizedFileURL.path != URL(fileURLWithPath: "\(paths.installDirectory)/Public").standardizedFileURL.path {
            try SetupFileSystem.copyReplacing(source: publicDirectory, destination: "\(paths.installDirectory)/Public")
        }
        if FileManager.default.fileExists(atPath: resourcesDirectory),
           URL(fileURLWithPath: resourcesDirectory).standardizedFileURL.path != URL(fileURLWithPath: "\(paths.installDirectory)/Resources").standardizedFileURL.path {
            try SetupFileSystem.copyReplacing(source: resourcesDirectory, destination: "\(paths.installDirectory)/Resources")
        }

        if let versionFile,
           FileManager.default.fileExists(atPath: versionFile),
           URL(fileURLWithPath: versionFile).standardizedFileURL.path != URL(fileURLWithPath: "\(paths.installDirectory)/.version").standardizedFileURL.path {
            try SetupFileSystem.copyReplacing(source: versionFile, destination: "\(paths.installDirectory)/.version")
        }

        try await Shell.runThrowing("chown", ["-R", "\(context.serviceUser):\(context.serviceUser)", paths.installDirectory])
    }

    private func writeReleaseVersion(_ tagName: String) async throws {
        let paths = try context.requirePaths()
        try await SetupFileSystem.writeFile(tagName, to: "\(paths.installDirectory)/.version", owner: context.serviceUser, group: context.serviceUser)
    }

    private func fetchLatestRelease() async throws -> (tagName: String, downloadURL: String) {
        guard let apiURL = URL(string: "https://api.github.com/repos/mottzi/Vapor-Deployer/releases/latest") else {
            throw SetupCommand.Error.releaseAssetNotFound("invalid API URL")
        }

        var request = URLRequest(url: apiURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tagName = json["tag_name"] as? String,
              let assets = json["assets"] as? [[String: Any]] else {
            throw SetupCommand.Error.releaseAssetNotFound("malformed release response")
        }

        let arch = try await Shell.runThrowing("uname", ["-m"]).trimmed
        let preferredAsset = "deployer-linux-\(arch).tar.gz"
        let downloadURL = assets
            .first(where: { ($0["name"] as? String) == preferredAsset })
            .flatMap { $0["browser_download_url"] as? String }
            ?? assets
            .first(where: { ($0["name"] as? String) == "deployer.tar.gz" })
            .flatMap { $0["browser_download_url"] as? String }

        guard let downloadURL else {
            throw SetupCommand.Error.releaseAssetNotFound(preferredAsset)
        }

        return (tagName, downloadURL)
    }
    
}
