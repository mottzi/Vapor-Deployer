import Vapor

/// Resolves whether setup can preserve the installed webhook identity or must synchronize a new one with GitHub.
struct SetupWebhookPlanner {

    let console: any Console

    func collect(
        owner: String,
        repository: String,
        webhookURL: String,
        previousMetadata: [String: String]?,
        existingSecret: String?
    ) async throws -> Plan {

        console.section("GitHub webhook setup")

        if identityIsUnchanged(
            owner: owner,
            repository: repository,
            webhookURL: webhookURL,
            previousMetadata: previousMetadata
        ), let secret = reusableSecret(existingSecret) {
            console.print("Webhook destination and repository are unchanged.")

            let forceSync = console.confirm(
                "Force sync webhook with GitHub? (Requires Access Token)",
                defaultYes: false
            )

            if !forceSync {
                console.print("Reusing existing webhook secret. Skipping GitHub API sync.")
                return Plan(secret: secret, githubToken: "")
            }
        }

        let secret = try generateHexSecret()
        let githubToken = try await collectGitHubToken(owner: owner, repository: repository)
        return Plan(secret: secret, githubToken: githubToken)
    }

}

extension SetupWebhookPlanner {

    /// Stable webhook choices produced by intake and consumed by the later provisioning step.
    struct Plan {
        let secret: String
        let githubToken: String
    }

}

extension SetupWebhookPlanner {

    private func identityIsUnchanged(
        owner: String,
        repository: String,
        webhookURL: String,
        previousMetadata: [String: String]?
    ) -> Bool {
        guard let previousMetadata,
              let previousRepositoryURL = previousMetadata["APP_REPO_URL"],
              let previousRepository = repositoryIdentity(from: previousRepositoryURL),
              let previousDomain = previousMetadata["PRIMARY_DOMAIN"],
              let previousWebhookPath = previousMetadata["WEBHOOK_PATH"] else {
            return false
        }

        let currentRepository = "\(owner)/\(repository)".lowercased()
        let previousWebhookURL =
            InputValidator.normalizeBaseURL("https://\(previousDomain)") + previousWebhookPath

        return currentRepository == previousRepository && webhookURL == previousWebhookURL
    }

    private func repositoryIdentity(from url: String) -> String? {
        if let parsed = InputValidator.parseGitHubSSHURL(url) {
            return "\(parsed.owner)/\(parsed.repo)".lowercased()
        }

        guard url.contains("github.com/") else { return nil }

        let parts = url.trimmingSuffix(".git").split(separator: "/")
        guard parts.count >= 2 else { return nil }

        return "\(parts[parts.count - 2])/\(parts[parts.count - 1])".lowercased()
    }

    private func reusableSecret(_ secret: String?) -> String? {
        guard let secret = secret?.trimmingCharacters(in: .whitespacesAndNewlines),
              !secret.isEmpty else {
            return nil
        }
        return secret
    }

    private func collectGitHubToken(owner: String, repository: String) async throws -> String {

        console.section("GitHub webhook access")

        console.card(
            "How to create the GitHub token",
            keyedValues: [
                ("Browser", "https://github.com/settings/tokens"),
                ("Click", "Generate new token > Generate new token (classic)"),
                ("Select", "admin:repo_hook")
            ]
        )

        while true {
//            let token = console.askSecret("GitHub token")
            let token = console.askRequired("GitHub token")
            do {
                try await verifyGitHubAccess(
                    token: token,
                    owner: owner,
                    repository: repository
                )
                return token
            } catch {
                console.warning(error.localizedDescription)
            }
        }
    }

    /// Generates a cryptographically secure 64-character payload used to sign and verify incoming GitHub webhooks.
    private func generateHexSecret() throws -> String {

        guard let handle = FileHandle(forReadingAtPath: "/dev/urandom") else {
            throw SetupCommand.Error.fileOperationFailed("/dev/urandom", CocoaError(.fileReadNoSuchFile))
        }

        let data = handle.readData(ofLength: 32)
        try? handle.close()

        return data.map { String(format: "%02x", $0) }.joined()
    }

    /// Asserts that the provided personal access token has sufficient permissions to manage webhooks for the target repository.
    private func verifyGitHubAccess(token: String, owner: String, repository: String) async throws {

        let urlString = "https://api.github.com/repos/\(owner)/\(repository)/hooks?per_page=1"
        guard let url = URL(string: urlString) else {
            throw SetupCommand.Error.githubAPI("invalid hooks URL")
        }

        let (_, status) = try await GitHub.API.request(url: url, token: token)
        guard (200..<300).contains(status) else {
            throw SetupCommand.Error.githubAPI(
                "token check failed for \(owner)/\(repository) (HTTP \(status))"
            )
        }
    }

}
