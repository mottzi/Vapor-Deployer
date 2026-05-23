import Vapor

/// Result of a preflight query to `GET /control/state`. Callers translate this into their own
/// error vocabulary and handle `.unreachable` with a context-appropriate warning message.
enum ControlPreflightOutcome {
    case ready
    case busy(phase: String)
    case unhealthy(reason: String)
    case unreachable(reason: String)
}

/// Shared helper for the `GET /control/state` preflight check performed by CLI commands before
/// disruptive operations. Handles token loading, HTTP transport, response decoding, and status-code
/// mapping in one place. Each caller translates the outcome into its own error vocabulary and prints
/// its own warning for `.unreachable`. See `docs/adr/0005-cli-server-state-channel.md`.
enum ControlPreflight {

    static func query(app: Application, port: Int, installDirectory: URL) async -> ControlPreflightOutcome {

        guard let token = ControlToken.loadOrGenerate(installDirectory: installDirectory) else {
            // No token file and generation failed. If a server is running it has the same problem
            // and won't have mounted /control — treat as unhealthy rather than silently proceeding.
            return .unhealthy(reason: "control token unavailable")
        }

        let uri = URI(string: "http://127.0.0.1:\(port)/control/state")

        let response: ClientResponse
        do {
            let headers = HTTPHeaders([("Authorization", "Bearer \(token.value)")])
            response = try await app.client.get(uri, headers: headers)
        } catch {
            // Vapor's client surfaces connection-refused as a thrown transport error.
            return .unreachable(reason: error.localizedDescription)
        }

        switch response.status {
            case .ok:
                let decoded: ControlStateResponse
                do { decoded = try response.content.decode(ControlStateResponse.self) }
                catch { return .unhealthy(reason: "control response could not be decoded: \(error.localizedDescription)") }
                if decoded.phase == DeployerPhase.ready.rawValue { return .ready }
                return .busy(phase: decoded.phase)
                    
            case .unauthorized, .forbidden:
                return .unhealthy(reason: "control token rejected (\(response.status.code))")
                    
            case .notFound:
                return .unhealthy(reason: "control endpoint missing — server may need restart")
                    
            default:
                return .unhealthy(reason: "server returned \(response.status.code)")
        }
    }

}
