import Foundation

/// A service manager implementation that delegates to `supervisorctl`.
struct SupervisorServiceManager: ServiceManager {

    func start(product: String) async throws {
        try await Shell.runThrowing("supervisorctl start \(product)")
    }

    func restart(product: String) async throws {
        try await Shell.runThrowing("supervisorctl restart \(product)")
    }

    func stop(product: String) async throws {
        try await Shell.runThrowing("supervisorctl stop \(product)")
    }

    func status(product: String) async -> ServiceStatus {

        let output = await Shell.run("supervisorctl status \(product)").output
        let arguments = output.split(whereSeparator: { $0.isWhitespace })
        guard let stateToken = arguments.dropFirst().first else { return .unknown }
        let stateString = String(stateToken)
        
        return ServiceStatus(rawValue: stateString) ?? .unknown
    }

}
