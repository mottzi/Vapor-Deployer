import Vapor
import Foundation

struct AppCheckoutStep: SetupStep {

    let context: SetupContext
    let console: any Console

    let title = "Preparing target app checkout"

    func run() async throws {
        let paths = try context.requirePaths()
        let sshCommand = "ssh -i \(paths.deployKeyPath) -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes"

        if FileManager.default.fileExists(atPath: "\(paths.appDirectory)/.git") {
            try await shell.runAsServiceUser("git", ["-C", paths.appDirectory, "config", "core.sshCommand", sshCommand])
            try await shell.runAsServiceUser("git", ["-C", paths.appDirectory, "fetch", "origin", context.appBranch, "--prune"])
            try await shell.runAsServiceUser("git", ["-C", paths.appDirectory, "checkout", context.appBranch])
            try await shell.runAsServiceUser("git", ["-C", paths.appDirectory, "pull", "--ff-only", "origin", context.appBranch])
            console.print("App checkout updated.")
        } else {
            try await SetupFileSystem.installDirectory(paths.appsRootDirectory, owner: context.serviceUser, group: context.serviceUser)
            try await shell.runAsServiceUser(
                "git clone",
                [context.appRepositoryURL, paths.appDirectory],
                environment: ["GIT_SSH_COMMAND": sshCommand]
            )
            try await shell.runAsServiceUser("git", ["-C", paths.appDirectory, "config", "core.sshCommand", sshCommand])
            try await shell.runAsServiceUser("git", ["-C", paths.appDirectory, "checkout", context.appBranch])
            console.print("App checkout ready.")
        }
    }

}
