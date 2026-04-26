import Foundation

/// A service manager implementation that delegates to `systemctl`.
struct SystemdServiceManager: ServiceManager {

    let serviceUser: String?

    func start(product: String) async throws {
        try await runUserSystemctl("start", product: product)
    }

    func restart(product: String) async throws {
        try await runUserSystemctl("restart", product: product)
    }

    func stop(product: String) async throws {
        try await runUserSystemctl("stop", product: product)
    }

    func status(product: String) async -> ServiceStatus {

        let output: String
        do {
            output = try await runUserSystemctl("is-active", product: product)
        } catch {
            output = (error as? Shell.Error)?.output ?? ""
        }

        let statusToken = output
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .reversed()
            .first(where: { ["active", "activating", "deactivating", "inactive", "failed"].contains($0) })
        
        return switch statusToken {
            case "active": .running
            case "activating": .starting
            case "deactivating": .stopping
            case "inactive": .stopped
            case "failed": .fatal
            default: .unknown
        }
    }

    @discardableResult
    private func runUserSystemctl(_ command: String, product: String) async throws -> String {
        try await SystemShell.runUserSystemctl(
            user: serviceUser,
            command: command,
            arguments: ["\(product).service"]
        )
    }

}
