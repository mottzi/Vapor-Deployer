import Vapor

extension Deployer {

    /// Mounts the `/control/state` endpoint used by CLI commands to query deployer phase before performing
    /// disruptive operations (self-update, future config-restart). Localhost-only via the existing HTTP
    /// listener (Vapor binds 127.0.0.1 by default; nginx does not proxy /control). Bearer-token authenticated
    /// against `<installDir>/.deployer-control.token`. See `docs/adr/0005-cli-server-state-channel.md`.
    func configureControl() throws {

        let executableURL = try Configuration.getExecutableURL()
        let installDirectory = executableURL.standardizedFileURL.resolvingSymlinksInPath().deletingLastPathComponent()

        guard let token = ControlToken.loadOrGenerate(installDirectory: installDirectory) else {
            app.logger.warning("Control token could not be provisioned; /control route will not be mounted.")
            return
        }

        let middleware = ControlBearerMiddleware(expected: token.value)
        let control = app.grouped("control").grouped(middleware)

        control.get("state") { request async -> ControlStateResponse in
            let isUpdating = await request.application.deployer.updater.isUpdating
            let isDeploying = await request.application.deployer.queue.isDeploying

            let phase: DeployerPhase = switch (isUpdating, isDeploying) {
                case (true, _): .updating
                case (_, true): .deploying
                case (false, false): .ready
            }

            return ControlStateResponse(phase: phase.rawValue)
        }
    }

}

/// Single-field payload returned by `GET /control/state`. Kept minimal — see ADR 0005 Q3.
struct ControlStateResponse: Content {
    let phase: String
}

/// Constant-time Bearer-token check on the `Authorization` header. Returns 401 on missing/mismatched tokens.
struct ControlBearerMiddleware: AsyncMiddleware {

    let expected: String

    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {

        guard let header = request.headers.bearerAuthorization?.token else { throw Abort(.unauthorized) }
        guard constantTimeEquals(header, expected) else { throw Abort(.unauthorized) }
        return try await next.respond(to: request)
    }

    private func constantTimeEquals(_ a: String, _ b: String) -> Bool {

        let aBytes = Array(a.utf8)
        let bBytes = Array(b.utf8)
        guard aBytes.count == bBytes.count else { return false }

        var diff: UInt8 = 0
        for i in 0..<aBytes.count { diff |= aBytes[i] ^ bBytes[i] }
        return diff == 0
    }

}
