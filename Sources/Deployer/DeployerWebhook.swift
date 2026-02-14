import Vapor

extension Deployer
{
    func useWebhook(config: DeployerConfiguration)
    {
        DeployerWebhook.register(using: config.server, on: self.app)
        { request, serverConfig async in
            
            let pipeline = DeploymentPipeline(pipeline: serverConfig, deployer: config, on: app)
            await pipeline.deploy(message: request.commitMessage)
        }
        
        DeployerWebhook.register(using: config.deployer, on: self.app)
        { request, deployerConfig async in
            
            let pipeline = DeploymentPipeline(pipeline: deployerConfig, deployer: config, on: app)
            await pipeline.deploy(message: request.commitMessage)
        }
    }
}

struct DeployerWebhook
{
    static func register(
        using config: PipelineConfiguration,
        on app: Application,
        onPush: @Sendable @escaping (Request, PipelineConfiguration) async -> Void
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
