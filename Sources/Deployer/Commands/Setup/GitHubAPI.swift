import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Thin GitHub REST wrapper that centralizes API-version pinning, header setup, status checking, and JSON decoding.
enum GitHubAPI {

    /// Issues a GitHub REST request with the pinned API version header and optional bearer authentication.
    static func request(
        method: String = "GET",
        url: URL,
        token: String? = nil,
        body: Data? = nil
    ) async throws -> (data: Data, status: Int) {

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (data, status)
    }

    /// Issues a GitHub REST request, enforces a 2xx status, and returns the decoded JSON body; empty bodies decode to an empty dictionary.
    @discardableResult
    static func requestJSON(
        method: String = "GET",
        url: URL,
        token: String? = nil,
        body: Data? = nil
    ) async throws -> Any {

        let (data, status) = try await request(method: method, url: url, token: token, body: body)
        guard (200..<300).contains(status) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(status)"
            throw SetupCommand.Error.githubAPI(message)
        }
        guard !data.isEmpty else { return [:] }
        return try JSONSerialization.jsonObject(with: data)
    }

    /// Parses a string URL and forwards to `requestJSON(method:url:token:body:)`; rejects malformed URLs with a standard `githubAPI` error.
    @discardableResult
    static func requestJSON(
        method: String = "GET",
        url rawURL: String,
        token: String? = nil,
        body: Data? = nil
    ) async throws -> Any {

        guard let url = URL(string: rawURL) else {
            throw SetupCommand.Error.githubAPI("invalid URL '\(rawURL)'")
        }
        return try await requestJSON(method: method, url: url, token: token, body: body)
    }

}
