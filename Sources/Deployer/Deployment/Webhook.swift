import Vapor

extension Deployer {
    
    func useWebhook(config: Configuration) {
        Webhook.register(using: config.target, on: app) { event, target async in
            await app.deployer.queue.recordPush(event: event, target: target)
        }
    }
    
}

struct Webhook {
    
    static func register(
        using config: TargetConfiguration,
        on app: Application,
        onPush: @Sendable @escaping (PushEvent, TargetConfiguration) async -> Void
    ) {
        let accepted = Response(status: .ok, body: .init(stringLiteral: "[\(config.name)] Push event accepted."))
        let denied = Response(status: .forbidden, body: .init(stringLiteral: "[\(config.name)] Push event denied."))
        let unsupportedEvent = Response(status: .badRequest, body: .init(stringLiteral: "[\(config.name)] Unsupported GitHub event."))
        let invalidPayload = Response(status: .badRequest, body: .init(stringLiteral: "[\(config.name)] Invalid push payload."))
        let ignoredDeletedPush = Response(status: .ok, body: .init(stringLiteral: "[\(config.name)] Deleted push ignored."))
        
        app.post(config.pusheventPath.pathComponents) { request async -> Response in
            
            guard validateSignature(of: request) else { return denied }
            guard validateEvent(of: request) else { return unsupportedEvent }
            guard let pushEvent = request.pushEvent else { return invalidPayload }
            guard pushEvent.deleted == false else { return ignoredDeletedPush }
            
            Task.detached { await onPush(pushEvent, config) }
            return accepted
        }
    }
    
    static func validateSignature(of request: Request) -> Bool {
        
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
    
    static func validateEvent(of request: Request) -> Bool {
        request.headers.first(name: "X-GitHub-Event") == "push"
    }
}

extension StringProtocol
{
    var hexadecimalData: Data? {
        
        guard count % 2 == 0 else { return nil }

        var data = Data(capacity: count / 2)
        var index = startIndex

        while index < endIndex {
            let byteEnd = self.index(index, offsetBy: 2)
            guard let byte = UInt8(self[index ..< byteEnd], radix: 16) else { return nil }
            data.append(byte)
            index = byteEnd
        }
        
        return data
    }
}

struct PushPayload: Codable {
    
    let after: String
    let ref: String
    let deleted: Bool
    let headCommit: Commit?
    
    struct Commit: Codable {
        let message: String
    }
    
}
 
struct PushEvent: Sendable {
    
    let branch: String
    let commitID: String
    let commitMessage: String?
    let deleted: Bool

    var deploymentMessage: String {
        commitMessage ?? "Commit \(String(commitID.prefix(8)))"
    }
    
}

extension Request {
    
    var pushEvent: PushEvent? {
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        guard let bodyBuffer = body.data else { return nil }
        guard let jsonData = bodyBuffer.getData(at: bodyBuffer.readerIndex, length: bodyBuffer.readableBytes) else { return nil }
        guard let payload = try? decoder.decode(PushPayload.self, from: jsonData) else { return nil }
        guard payload.after.isEmpty == false, payload.ref.isEmpty == false else { return nil }
        
        return PushEvent(
            branch: payload.ref,
            commitID: payload.after,
            commitMessage: payload.headCommit?.message,
            deleted: payload.deleted
        )
    }
}
