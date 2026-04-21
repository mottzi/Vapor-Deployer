import Vapor
import Foundation

struct WebhookStep: SetupStep {

    let context: SetupContext
    let console: any Console

    let title = "Creating GitHub webhook"

    func run() async throws {
        
        let hooks = try await GitHubAPI.requestJSON(url: hooksURL(), token: context.githubToken)
        let existingID = (hooks as? [[String: Any]])?
            .first { hook in
                guard let config = hook["config"] as? [String: Any] else { return false }
                return config["url"] as? String == context.webhookURL
            }?["id"]

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
        let data = try JSONSerialization.data(withJSONObject: payload)

        if let existingID {
            try await GitHubAPI.requestJSON(method: "PATCH", url: "\(hooksURL())/\(existingID)", token: context.githubToken, body: data)
            console.print("Updated existing GitHub webhook.")
        } else {
            try await GitHubAPI.requestJSON(method: "POST", url: hooksURL(), token: context.githubToken, body: data)
            console.print("Created GitHub webhook.")
        }
    }

    private func hooksURL() -> String {
        "https://api.github.com/repos/\(context.githubOwner)/\(context.githubRepo)/hooks"
    }

}
