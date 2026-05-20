import Vapor

extension Deployer {

    /// Mounts the `/admin/state` endpoint used by CLI commands to query deployer phase before performing
    /// disruptive operations (self-update, future config-restart). Localhost-only via the existing HTTP
    /// listener (Vapor binds 127.0.0.1 by default; nginx does not proxy /admin). Bearer-token authenticated
    /// against `<installDir>/.deployer-admin.token`. See `docs/adr/0005-cli-server-state-channel.md`.
    func configureAdmin() throws {

        let executableURL = try Configuration.getExecutableURL()
        let installDirectory = executableURL.standardizedFileURL.resolvingSymlinksInPath().deletingLastPathComponent()

        guard let token = AdminToken.loadOrGenerate(installDirectory: installDirectory) else {
            app.logger.warning("Admin token could not be provisioned; /admin route will not be mounted.")
            return
        }

        let middleware = AdminBearerMiddleware(expected: token.value)
        let admin = app.grouped("admin").grouped(middleware)

        admin.get("state") { request async -> AdminStateResponse in
            let isUpdating = await request.application.deployer.updater.isUpdating
            let isDeploying = await request.application.deployer.queue.isDeploying

            let phase: DeployerPhase = isUpdating ? .updating
                : (isDeploying ? .deploying : .ready)

            return AdminStateResponse(phase: phase.rawValue)
        }
    }

}

/// Single-field payload returned by `GET /admin/state`. Kept minimal — see ADR 0005 Q3.
struct AdminStateResponse: Content {
    let phase: String
}

/// Constant-time Bearer-token check on the `Authorization` header. Returns 401 on missing/mismatched tokens.
struct AdminBearerMiddleware: AsyncMiddleware {

    let expected: String

    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        guard let header = request.headers.bearerAuthorization?.token,
              constantTimeEquals(header, expected) else {
            throw Abort(.unauthorized)
        }
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
