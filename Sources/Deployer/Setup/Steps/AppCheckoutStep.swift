import Vapor
import Foundation

struct AppCheckoutStep: SetupStep {

    let title = "Preparing target app checkout"

    func run(context: SetupContext, console: any Console) async throws {
        let paths = try context.requirePaths()
        let sshCommand = "ssh -i \(paths.deployKeyPath) -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes"

        if FileManager.default.fileExists(atPath: "\(paths.appDirectory)/.git") {
            try await UserShell.runAsServiceUser(context, ["git", "-C", paths.appDirectory, "config", "core.sshCommand", sshCommand])
            try await UserShell.runAsServiceUser(context, ["git", "-C", paths.appDirectory, "fetch", "origin", context.appBranch, "--prune"])
            try await UserShell.runAsServiceUser(context, ["git", "-C", paths.appDirectory, "checkout", context.appBranch])
            try await UserShell.runAsServiceUser(context, ["git", "-C", paths.appDirectory, "pull", "--ff-only", "origin", context.appBranch])
            console.print("App checkout updated.")
        } else {
            try await SetupFileSystem.installDirectory(paths.appsRootDirectory, owner: context.serviceUser, group: context.serviceUser)
            try await UserShell.runAsServiceUser(
                context,
                ["git", "clone", context.appRepositoryURL, paths.appDirectory],
                environment: ["GIT_SSH_COMMAND": sshCommand]
            )
            try await UserShell.runAsServiceUser(context, ["git", "-C", paths.appDirectory, "config", "core.sshCommand", sshCommand])
            try await UserShell.runAsServiceUser(context, ["git", "-C", paths.appDirectory, "checkout", context.appBranch])
            console.print("App checkout ready.")
        }
    }

}
