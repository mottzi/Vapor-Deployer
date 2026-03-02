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
            
            guard validateSignature2(of: request) else { return denied }
            Task.detached { await onPush(request, config) }
            return accepted
        }
    }
    
    static func validateSignature(of request: Request) -> Bool
    {
        let secret = DeployerVariables.GITHUB_WEBHOOK_SECRET.value
        guard let secretData = secret.data(using: .utf8) else { return false }

        guard let signatureHeader = request.headers.first(name: "X-Hub-Signature-256") else { return false }
        guard signatureHeader.hasPrefix("sha256=") else { return false }
        let signatureHex = String(signatureHeader.dropFirst("sha256=".count))

        guard let payload = request.body.string else { return false }
        guard let payloadData = payload.data(using: .utf8) else { return false }

        let secretDataKey = SymmetricKey(data: secretData)
        let signature = HMAC<SHA256>.authenticationCode(for: payloadData, using: secretDataKey)
        let expectedSignatureHex = signature.map { String(format: "%02x", $0) }.joined()
        guard expectedSignatureHex.count == signatureHex.count else { return false }

        return HMAC<SHA256>.isValidAuthenticationCode(
            signatureHex.hexadecimal ?? Data(),
            authenticating: payloadData,
            using: secretDataKey
        )
    }
    
    static func validateSignature2(of request: Request) -> Bool
    {
        let secret = DeployerVariables.GITHUB_WEBHOOK_SECRET.value

        guard let secretData = secret.data(using: .utf8),
              let sigHeader  = request.headers.first(name: "X-Hub-Signature-256"),
              sigHeader.hasPrefix("sha256=")
        else { return false }

        let signatureHex = sigHeader.dropFirst("sha256=".count)

        guard signatureHex.count == 64,
              let signatureData = signatureHex.hexadecimalData,
              let byteBuffer    = request.body.data,
              let payloadData   = byteBuffer.getData(at: byteBuffer.readerIndex, length: byteBuffer.readableBytes)
        else { return false }

        let key = SymmetricKey(data: secretData)

        return HMAC<SHA256>.isValidAuthenticationCode(
            signatureData,
            authenticating: payloadData,
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
            guard let byte = UInt8(self[index..<byteEnd], radix: 16) else { return nil }
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

extension String
{
    var hexadecimal: Data?
    {
        var data = Data(capacity: count / 2)
        let regex = try! NSRegularExpression(pattern: "[0-9a-f]{1,2}", options: .caseInsensitive)

        regex.enumerateMatches(in: self, range: NSRange(startIndex..., in: self))
        { match, _, _ in
            let byteString = (self as NSString).substring(with: match!.range)
            let num = UInt8(byteString, radix: 16)!
            data.append(num)
        }

        return data
    }
}
