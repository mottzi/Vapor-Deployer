import Vapor

/// Clones or updates the target application's Git repository using the service user's deploy key.
struct AppCheckoutStep: SetupStep {

    let context: SetupContext
    let console: any Console

    let title = "Preparing target app checkout"

    func run() async throws {
        FileManager.default.fileExists(atPath: "\(paths.appDirectory)/.git")
            ? try await updateRepository()
            : try await cloneRepository()
    }

}

extension AppCheckoutStep {

    private func updateRepository() async throws {

        try await shell.git("config", ["core.sshCommand", sshCommand], in: paths.appDirectory)
        try await shell.git("fetch", ["origin", context.appBranch, "--prune"], in: paths.appDirectory)
        try await shell.git("checkout", [context.appBranch], in: paths.appDirectory)
        try await shell.git("pull", ["--ff-only", "origin", context.appBranch], in: paths.appDirectory)
        console.print("App checkout updated.")
    }

    private func cloneRepository() async throws {

        try await SystemFileSystem.installDirectory(
            paths.appsRootDirectory,
            owner: context.serviceUser,
            group: context.serviceUser
        )

        try await shell.git(
            "clone",
            [context.appRepositoryURL, paths.appDirectory],
            environment: ["GIT_SSH_COMMAND": sshCommand]
        )

        try await shell.git("config", ["core.sshCommand", sshCommand], in: paths.appDirectory)
        try await shell.git("checkout", [context.appBranch], in: paths.appDirectory)
        console.print("App checkout ready.")
    }

}

extension AppCheckoutStep {
    
    private var sshCommand: String {
        "ssh -i \(paths.deployKeyPath) -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes"
    }
    
}
