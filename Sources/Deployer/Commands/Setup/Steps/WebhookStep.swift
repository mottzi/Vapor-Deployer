import Vapor

/// Provisions or updates a GitHub webhook to trigger deployments when code is pushed.
struct WebhookStep: SetupStep {

    let context: SetupContext
    let console: any Console

    let title = "Creating GitHub webhook"

    func run() async throws {
        guard !context.githubToken.isEmpty else {
            console.print("Skipping GitHub API sync (configuration unchanged).")
            return
        }
        
        let existingID = try await fetchExistingWebhookID()
        try await upsertWebhook(existingID: existingID)
    }

}

extension WebhookStep {

    private func fetchExistingWebhookID() async throws -> Any? {

        let hooks = try await GitHubAPI.requestJSON(url: hooksURL, token: context.githubToken)
        return (hooks as? [[String: Any]])?.first { hook in
            guard let config = hook["config"] as? [String: Any] else { return false }
            return config["url"] as? String == context.webhookURL
        }?["id"]
    }

    private func upsertWebhook(existingID: Any?) async throws {

        let data = try buildWebhookPayload()

        if let existingID {
            try await GitHubAPI.requestJSON(
                method: "PATCH", 
                url: "\(hooksURL)/\(existingID)", 
                token: context.githubToken, 
                body: data
            )
            console.print("Updated existing GitHub webhook.")
        } else {
            try await GitHubAPI.requestJSON(
                method: "POST", 
                url: hooksURL, 
                token: context.githubToken, 
                body: data
            )
            console.print("Created GitHub webhook.")
        }
    }

}

extension WebhookStep {

    private var hooksURL: String {
        "https://api.github.com/repos/\(context.githubOwner)/\(context.githubRepo)/hooks"
    }

    private func buildWebhookPayload() throws -> Data {

        let payload: [String: Any] = [
            "name": "web",
            "active": true,
            "events": ["push"],
            "config": [
                "url": context.webhookURL,
                "content_type": "json",
                "secret": context.webhookSecret,
                "insecure_ssl": "0"
            ]
        ]
        
        return try JSONSerialization.data(withJSONObject: payload)
    }

}
