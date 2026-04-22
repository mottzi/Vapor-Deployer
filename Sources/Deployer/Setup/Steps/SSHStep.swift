import Vapor

struct SSHStep: SetupStep {

    let context: SetupContext
    let console: any Console

    let title = "Preparing GitHub clone access"

    func run() async throws {
        try await prepareSSHDirectory()
        try await ensureDeployKey()
        try await ensureGitHubAccess()
    }

}

extension SSHStep {

    /// Bootstraps the service user's ~/.ssh directory and seeds GitHub's host key into known_hosts.
    private func prepareSSHDirectory() async throws {

        try await SetupFileSystem.installDirectory(
            "\(paths.serviceHome)/.ssh",
            mode: "0700",
            owner: context.serviceUser,
            group: context.serviceUser
        )

        try await shell.runAsServiceUser("touch", ["\(paths.serviceHome)/.ssh/known_hosts"])
        try await shell.runAsServiceUser("chmod", ["600", "\(paths.serviceHome)/.ssh/known_hosts"])
        _ = try? await shell.runAsServiceUser("bash", ["-c", "ssh-keyscan -H github.com >> ~/.ssh/known_hosts"])
    }

    /// Generates an ed25519 deploy key for this app if one does not already exist on disk.
    private func ensureDeployKey() async throws {

        if !FileManager.default.fileExists(atPath: paths.deployKeyPath) {
            try await shell.runAsServiceUser("ssh-keygen", [
                "-t", "ed25519",
                "-N", "",
                "-f", paths.deployKeyPath,
                "-C", "\(context.serviceUser)@\(ProcessInfo.processInfo.hostName)-\(context.appName)"
            ])
            console.print("Generated deploy key at \(paths.deployKeyPath).")
        } else {
            console.print("Reusing deploy key at \(paths.deployKeyPath).")
        }
    }

    /// Verifies repository access, prompting the operator to register the deploy key on GitHub if needed.
    private func ensureGitHubAccess() async throws {

        if try await canReachRepository() {
            console.print("GitHub clone access verified.")
            return
        }

        let publicKey = (try? String(contentsOfFile: "\(paths.deployKeyPath).pub", encoding: .utf8).trimmed) ?? ""

        console.lines(
            title: "Action required - Add deploy key to GitHub",
            lines: [
                "Open: https://github.com/\(context.githubOwner)/\(context.githubRepo)/settings/keys",
                "Title: \(context.appName)-deployer",
                "Access: leave write access disabled (read-only key)",
                "Public key:",
                publicKey
            ]
        )

        if !console.confirm("Continue after adding the deploy key on GitHub?", defaultYes: true) {
            throw SetupCommand.Error.invalidValue(
                "deployKey",
                "GitHub deploy key setup was not confirmed"
            )
        }

        if try await !canReachRepository() {
            throw SetupCommand.Error.invalidValue(
                "deployKey",
                "GitHub access check failed. Verify the deploy key and repository permissions."
            )
        }

        console.print("GitHub clone access verified.")
    }

}

extension SSHStep {

    /// Attempts a lightweight `git ls-remote` through the deploy key to confirm read access to the repository.
    private func canReachRepository() async throws -> Bool {

        let sshCommand = "ssh -i \(paths.deployKeyPath) -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes"

        do {
            try await shell.git(
                "ls-remote",
                [context.appRepositoryURL, context.appBranch],
                environment: ["GIT_SSH_COMMAND": sshCommand]
            )
            return true
        } catch {
            return false
        }
    }

}
