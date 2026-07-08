import Vapor

extension GitHub {

    /// Domain representation of a repository update, encapsulating reference tracking metadata required to run deployment builds.
    struct PushEvent {

        let branch: String
        let commitID: String
        let commitMessage: String?
        let deleted: Bool

        var deploymentMessage: String {
            commitMessage ?? "Commit \(String(commitID.prefix(8)))"
        }

    }

}

extension GitHub.PushEvent {

    /// Safely extracts git reference updates from request body data, returning nil to reject malformed webhook payloads early.
    static func parse(from request: Request) -> GitHub.PushEvent? {

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        guard let bodyBuffer = request.body.data else { return nil }
        guard let jsonData = bodyBuffer.getData(at: bodyBuffer.readerIndex, length: bodyBuffer.readableBytes) else { return nil }
        guard let payload = try? decoder.decode(Payload.self, from: jsonData) else { return nil }
        guard payload.after.isEmpty == false, payload.ref.isEmpty == false else { return nil }

        return GitHub.PushEvent(
            branch: payload.ref,
            commitID: payload.after,
            commitMessage: payload.headCommit?.message,
            deleted: payload.deleted
        )
    }

}

extension GitHub.PushEvent {
    
    /// Decouples the external GitHub wire-format payload from the application's internal Git and Deployment models.
    private struct Payload: Codable {

        let after: String
        let ref: String
        let deleted: Bool
        let headCommit: Commit?

        struct Commit: Codable {
            let message: String
        }

    }
    
}
