import Vapor

/// Removes the generated SSH deploy key and cleans up the SSH config reference.
struct RemoveSSHStep: RemoveStep {

    let context: RemoveContext
    let console: any Console

    let title = "Removing SSH deploy keys"

    func run() async throws {

        removeDeployKeyFiles()
        await pruneSSHConfig()

        console.print("SSH deploy key cleanup complete.")
    }

}

extension RemoveSSHStep {

    private func removeDeployKeyFiles() {

        let keyBase = paths.deployKeyPath

        let privateExists = FileManager.default.fileExists(atPath: keyBase)
        let publicExists = FileManager.default.fileExists(atPath: "\(keyBase).pub")

        if privateExists || publicExists {
            console.print("Removing deploy key files for app '\(context.appName)'.")
        }

        try? SystemFileSystem.removeIfPresent(keyBase)
        try? SystemFileSystem.removeIfPresent("\(keyBase).pub")
    }

    private func pruneSSHConfig() async {

        let sshConfig = "\(paths.serviceHome)/.ssh/config"

        guard FileManager.default.fileExists(atPath: sshConfig) else { return }

        await bestEffort("prune SSH config") {
            try await Shell.runThrowing(
                "sed", ["-i", "\\|\(paths.deployKeyPath)|d", sshConfig]
            )
            try await Shell.runThrowing(
                "sed", ["-i", "\\|deployer-managed-\(context.appName)|d", sshConfig]
            )
        }
    }

}
