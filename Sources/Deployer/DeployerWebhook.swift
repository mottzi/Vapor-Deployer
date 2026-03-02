import Vapor

extension Deployer
{
    func useWebhook(config: DeployerConfiguration)
    {
        DeployerWebhook.register(using: config.serverTarget, on: self.app)
        { request, serverConfig async in
            await app.deployer.queue.enqueue(
                message: request.commitMessage,
                target: serverConfig
            )
        }
        
        DeployerWebhook.register(using: config.deployerTarget, on: self.app)
        { request, deployerConfig async in
            await app.deployer.queue.enqueue(
                message: request.commitMessage,
                target: deployerConfig
            )
        }
    }
}

struct DeployerWebhook
{
    static func register(
        using config: TargetConfiguration,
        on app: Application,
        onPush: @Sendable @escaping (Request, TargetConfiguration) async -> Void
    ) {
        let accepted = Response(status: .ok, body: .init(stringLiteral: "[\(config.productName)] Push event accepted."))
        let denied = Response(status: .forbidden, body: .init(stringLiteral: "[\(config.productName)] Push event denied."))
        
        app.post(config.pusheventPath)
        { request async -> Response in
            
            guard validateSignature(of: request) else { return denied }
            Task.detached { await onPush(request, config) }
            return accepted
        }
    }
    
    static func validateSignature(of request: Request) -> Bool
    {
        let secret = DeployerVariables.GITHUB_WEBHOOK_SECRET.value

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

        return HMAC<SHA256>.isValidAuthenticationCode(
            signatureData,
            authenticating: bodyData,
            using: key
        )
    }
}

extension StringProtocol
{
    var hexadecimalData: Data?
    {
        guard count % 2 == 0 else { return nil }

        var data = Data(capacity: count / 2)
        var index = startIndex

        while index < endIndex
        {
            let byteEnd = self.index(index, offsetBy: 2)
            guard let byte = UInt8(self[index ..< byteEnd], radix: 16) else { return nil }
            data.append(byte)
            index = byteEnd
        }
        
        return data
    }
}

struct DeployerPayload: Codable
{
    let headCommit: Commit
    
    struct Commit: Codable
    {
        let message: String
    }
}

extension Request
{
    var payload: DeployerPayload?
    {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        guard let bodyString = body.string else { return nil }
        guard let jsonData = bodyString.data(using: .utf8) else { return nil }
        
        return try? decoder.decode(DeployerPayload.self, from: jsonData)
    }
    
    var commitMessage: String? { payload?.headCommit.message }
}
