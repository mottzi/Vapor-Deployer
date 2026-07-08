import Vapor

extension Deployer {

    /// Bootstraps webhook-driven continuous deployment during initialization by binding incoming git events to the background operations manager.
    func useGitHubWebhook(config: Configuration) {
        GitHub.Webhook.register(using: config.target, on: app) { event, target async in
            await app.deployer.operations.recordPush(event: event, target: target)
        }
    }

}

extension GitHub {

    /// Serves as the security gate and request router validating external git actions before triggering deployment tasks.
    struct Webhook {

        /// Sets up a public route that validates incoming HTTP notifications and offloads deployment pipelines to prevent network timeouts.
        static func register(
            using config: TargetConfiguration,
            on app: Application,
            onPush: @Sendable @escaping (GitHub.PushEvent, TargetConfiguration) async -> Void
        ) {

            app.post(config.pusheventPath.pathComponents) { request async -> Response in

                guard validateSignature(of: request) else {
                    request.logger.warning("[\(config.name)] GitHub webhook signature verification failed from \(request.remoteAddress?.description ?? "unknown IP")")
                    return Response(status: .forbidden, body: .init(stringLiteral: "[\(config.name)] Push event denied."))
                }

                guard validateEvent(of: request) else {
                    request.logger.warning("[\(config.name)] GitHub webhook event is unsupported (Event: \(request.headers.first(name: "X-GitHub-Event") ?? "none"))")
                    return Response(status: .badRequest, body: .init(stringLiteral: "[\(config.name)] Unsupported GitHub event."))
                }

                guard let pushEvent = GitHub.PushEvent.parse(from: request) else {
                    request.logger.warning("[\(config.name)] GitHub webhook invalid push payload")
                    return Response(status: .badRequest, body: .init(stringLiteral: "[\(config.name)] Invalid push payload."))
                }

                guard pushEvent.deleted == false else {
                    request.logger.info("[\(config.name)] Ignored deleted push event for branch '\(pushEvent.branch)'")
                    return Response(status: .ok, body: .init(stringLiteral: "[\(config.name)] Deleted push ignored."))
                }

                request.logger.info("[\(config.name)] Accepted GitHub push event for branch '\(pushEvent.branch)' at commit \(pushEvent.commitID)")

                Task.detached { await onPush(pushEvent, config) }

                return Response(status: .ok, body: .init(stringLiteral: "[\(config.name)] Push event accepted."))
            }
        }

    }

}

extension GitHub.Webhook {
    
    /// Prevents replay and spoofing attacks by asserting payload integrity using constant-time evaluation against a configured secret.
    private static func validateSignature(of request: Request) -> Bool {

        let secret = Deployer.Variables.GITHUB_WEBHOOK_SECRET.value

        guard let secretData = secret.data(using: .utf8),
              let signatureHeader = request.headers.first(name: "X-Hub-Signature-256"),
              signatureHeader.hasPrefix("sha256=")
        else { return false }

        let signatureHex = signatureHeader.dropFirst("sha256=".count)

        guard signatureHex.count == 64,
              let signatureData = signatureHex.hexadecimalData,
              let bodyBuffer = request.body.data,
              let bodyData = bodyBuffer.getData(at: bodyBuffer.readerIndex, length: bodyBuffer.readableBytes)
        else { return false }

        let key = SymmetricKey(data: secretData)

        return HMAC<SHA256>.isValidAuthenticationCode(signatureData, authenticating: bodyData, using: key)
    }

    /// Guards the endpoint from unnecessary processing by rejecting any non-push events before parsing payload contents.
    private static func validateEvent(of request: Request) -> Bool {
        request.headers.first(name: "X-GitHub-Event") == "push"
    }
    
}
