import Vapor

extension Application
{
    func useWebhook(config: Deployer.Configuration)
    {
        Deployer.Webhook.register(using: config.serverConfig, on: self)
        { request, config async in
            
            let pipeline = Deployer.Pipeline(config: config)
            await pipeline.deploy(message: request.commitMessage, on: self)
        }
        
        Deployer.Webhook.register(using: config.deployerConfig, on: self)
        { request, config async in
            
            let pipeline = Deployer.Pipeline(config: config)
            await pipeline.deploy(message: request.commitMessage, on: self)
        }
    }
}

extension Application.Deployer
{
    struct Webhook
    {
        static func register(
            using config: Pipeline.Configuration,
            on app: Application,
            onPush: @Sendable @escaping (Request, Pipeline.Configuration) async -> Void)
        {
            let accepted = Response(status: .ok, body: .init(stringLiteral: "[\(config.productName)] Push event accepted."))
            let denied = Response(status: .forbidden, body: .init(stringLiteral: "[\(config.productName)] Push event denied."))

            app.post(config.pusheventPath)
            { request async -> Response in
                
                guard validateSignature(of: request) else { return denied }
                Task.detached { await onPush(request, config) }
                return accepted
            }
        }

        private static func validateSignature(of request: Request) -> Bool 
        {
            let secret = Environment.Variables.GITHUB_WEBHOOK_SECRET.value
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
}

extension Application.Deployer.Webhook
{
    struct Payload: Codable
    {
        let headCommit: Commit

        struct Commit: Codable
        {
            let id: String
            let message: String
        }
    }
}

extension Request
{
    var commitMessage: String?
    {
        typealias Payload = Application.Deployer.Webhook.Payload
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        guard let bodyString = self.body.string else { return nil }
        guard let jsonData = bodyString.data(using: .utf8) else { return nil }
        guard let payload = try? decoder.decode(Payload.self, from: jsonData) else { return nil }
        
        return payload.headCommit.message
    }
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
