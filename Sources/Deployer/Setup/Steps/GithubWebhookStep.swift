import Vapor
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct GithubWebhookStep: SetupStep {

    let title = "Creating GitHub webhook"

    func run(context: SetupContext, console: any Console) async throws {
        let hooks = try await requestJSON(context: context, method: "GET", url: hooksURL(context), body: nil)
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
            try await requestJSON(context: context, method: "PATCH", url: "\(hooksURL(context))/\(existingID)", body: data)
            console.print("Updated existing GitHub webhook.")
        } else {
            try await requestJSON(context: context, method: "POST", url: hooksURL(context), body: data)
            console.print("Created GitHub webhook.")
        }
    }

    private func hooksURL(_ context: SetupContext) -> String {
        "https://api.github.com/repos/\(context.githubOwner)/\(context.githubRepo)/hooks"
    }

    @discardableResult
    private func requestJSON(context: SetupContext, method: String, url rawURL: String, body: Data?) async throws -> Any {
        guard let url = URL(string: rawURL) else { throw SetupCommand.Error.githubAPI("invalid URL '\(rawURL)'") }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("Bearer \(context.githubToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(status)"
            throw SetupCommand.Error.githubAPI(message)
        }

        guard !data.isEmpty else { return [:] }
        return try JSONSerialization.jsonObject(with: data)
    }

}
