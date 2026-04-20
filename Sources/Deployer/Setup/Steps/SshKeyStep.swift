import Vapor
import Foundation

struct SshKeyStep: SetupStep {

    let title = "Preparing GitHub clone access"

    func run(context: SetupContext, console: any Console) async throws {
        let paths = try context.requirePaths()

        try await SetupFileSystem.installDirectory("\(paths.serviceHome)/.ssh", mode: "0700", owner: context.serviceUser, group: context.serviceUser)
        try await SetupUserShell.runAsServiceUser(context, ["touch", "\(paths.serviceHome)/.ssh/known_hosts"])
        try await SetupUserShell.runAsServiceUser(context, ["chmod", "600", "\(paths.serviceHome)/.ssh/known_hosts"])
        _ = try? await SetupUserShell.runAsServiceUser(context, ["bash", "-c", "ssh-keyscan -H github.com >> ~/.ssh/known_hosts"])

        if !FileManager.default.fileExists(atPath: paths.deployKeyPath) {
            try await SetupUserShell.runAsServiceUser(context, [
                "ssh-keygen",
                "-t", "ed25519",
                "-N", "",
                "-f", paths.deployKeyPath,
                "-C", "\(context.serviceUser)@\(ProcessInfo.processInfo.hostName)-\(context.appName)"
            ])
            console.print("Generated deploy key at \(paths.deployKeyPath).")
        } else {
            console.print("Reusing deploy key at \(paths.deployKeyPath).")
        }

        if try await verifyRepoAccess(context) {
            console.print("GitHub clone access verified.")
            return
        }

        let publicKey = (try? String(contentsOfFile: "\(paths.deployKeyPath).pub", encoding: .utf8).trimmed) ?? ""
        SetupCard.lines(
            title: "Action required - Add deploy key to GitHub",
            lines: [
                "Open: https://github.com/\(context.githubOwner)/\(context.githubRepo)/settings/keys",
                "Title: \(context.appName)-deployer",
                "Access: leave write access disabled (read-only key)",
                "Public key:",
                publicKey
            ],
            console: console
        )

        guard SetupPrompt.confirm("Continue after adding the deploy key on GitHub?", defaultYes: true, console: console) else {
            throw SetupCommand.Error.invalidValue("deployKey", "GitHub deploy key setup was not confirmed")
        }

        guard try await verifyRepoAccess(context) else {
            throw SetupCommand.Error.invalidValue("deployKey", "GitHub access check failed. Verify the deploy key and repository permissions.")
        }

        console.print("GitHub clone access verified.")
    }

    private func verifyRepoAccess(_ context: SetupContext) async throws -> Bool {
        let paths = try context.requirePaths()
        let sshCommand = "ssh -i \(paths.deployKeyPath) -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes"
        do {
            _ = try await SetupUserShell.runAsServiceUser(
                context,
                ["git", "ls-remote", context.appRepositoryURL, context.appBranch],
                environment: ["GIT_SSH_COMMAND": sshCommand]
            )
            return true
        } catch {
            return false
        }
    }

}
