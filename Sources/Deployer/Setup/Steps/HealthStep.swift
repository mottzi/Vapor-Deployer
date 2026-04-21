import Vapor
import Foundation

struct HealthStep: SetupStep {

    let context: SetupContext
    let console: any Console

    let title = "Running health checks"

    func run() async throws {
        
        try await waitForService("deployer")
        console.print("Deployer service is running.")

        try await waitForService(context.productName)
        console.print("App service is running.")

        try await waitForTCP(port: context.deployerPort)
        console.print("Deployer listening on 127.0.0.1:\(context.deployerPort).")

        try await waitForTCP(port: context.appPort)
        console.print("App listening on 127.0.0.1:\(context.appPort).")

        let paths = try context.requirePaths()
        guard FileManager.default.isExecutableFile(atPath: "\(paths.appDeployDirectory)/\(context.productName)")
        else { throw SetupCommand.Error.invalidValue("app binary", "missing deployed app binary") }
    }

    private func waitForService(_ service: String) async throws {
        for _ in 0..<30 {
            if await isServiceRunning(service) { return }
            try await Task.sleep(for: .seconds(1))
        }

        throw SetupCommand.Error.serviceTimeout(service)
    }

    private func isServiceRunning(_ service: String) async -> Bool {
        switch context.serviceManagerKind {
        case .systemd:
            let output = try? await shell.runUserSystemctl("is-active", ["\(service).service"])
            return output?.trimmed == "active"
        case .supervisor:
            let status = await Shell.run("supervisorctl", ["status", service]).output
            return status.split(whereSeparator: { $0.isWhitespace }).dropFirst().first == "RUNNING"
        }
    }

    private func waitForTCP(port: Int) async throws {
        for _ in 0..<30 {
            let result = await Shell.run("exec 3<>/dev/tcp/127.0.0.1/\(port)")
            if result.exitCode == 0 { return }
            try await Task.sleep(for: .seconds(1))
        }

        throw SetupCommand.Error.serviceTimeout("127.0.0.1:\(port)")
    }

}
