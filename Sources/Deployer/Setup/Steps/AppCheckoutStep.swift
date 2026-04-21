import Vapor
import Foundation

struct AppCheckoutStep: SetupStep {

    let context: SetupContext
    let console: any Console

    let title = "Preparing target app checkout"

    func run() async throws {
        let sshCommand = "ssh -i \(paths.deployKeyPath) -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes"

        if FileManager.default.fileExists(atPath: "\(paths.appDirectory)/.git") {
            try await shell.git("config", ["core.sshCommand", sshCommand], in: paths.appDirectory)
            try await shell.git("fetch", ["origin", context.appBranch, "--prune"], in: paths.appDirectory)
            try await shell.git("checkout", [context.appBranch], in: paths.appDirectory)
            try await shell.git("pull", ["--ff-only", "origin", context.appBranch], in: paths.appDirectory)
            console.print("App checkout updated.")
        } else {
            try await SetupFileSystem.installDirectory(paths.appsRootDirectory, owner: context.serviceUser, group: context.serviceUser)
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

}
