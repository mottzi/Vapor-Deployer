import Foundation

/// A service manager implementation that delegates to `supervisorctl`.
struct SupervisorServiceManager: ServiceManager {

    func start(product: String) async throws {
        try await Shell.execute("supervisorctl start \(product)")
    }

    func restart(product: String) async throws {
        try await Shell.execute("supervisorctl restart \(product)")
    }

    func stop(product: String) async throws {
        try await Shell.execute("supervisorctl stop \(product)")
    }

    func status(product: String) async -> ServiceStatus {

        let output = await Shell.executeRaw("supervisorctl status \(product)")
        let arguments = output.split(whereSeparator: { $0.isWhitespace })
        guard let stateToken = arguments.dropFirst().first else { return .unknown }
        let stateString = String(stateToken)
        
        return ServiceStatus(rawValue: stateString) ?? .unknown
    }

}
