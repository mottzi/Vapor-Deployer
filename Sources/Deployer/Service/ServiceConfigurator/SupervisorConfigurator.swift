import Foundation

/// Setup/teardown operations for Supervisor programs.
struct SupervisorConfigurator: ServiceConfigurator {

    func isRunning(_ service: String) async -> Bool {
        let status = await Shell.run("supervisorctl", ["status", service]).output
        return status.split(whereSeparator: { $0.isWhitespace }).dropFirst().first == "RUNNING"
    }

    func disable(_ products: [String]) async {
        for product in products {
            await Shell.run("supervisorctl", ["stop", product])
        }
    }

    func removeConfigs(for products: [String]) async {
        for product in products {
            try? SystemFileSystem.removeIfPresent("/etc/supervisor/conf.d/\(product).conf")
        }
        await Shell.run("supervisorctl", ["reread"])
        await Shell.run("supervisorctl", ["update"])
    }

    func enableAndStart(_ products: [String]) async throws {
        try await Shell.runThrowing("systemctl", ["enable", "--now", "supervisor"])
        try await Shell.runThrowing("supervisorctl", ["reread"])
        try await Shell.runThrowing("supervisorctl", ["update"])

        for product in products {
            let restart = await Shell.run("supervisorctl", ["restart", product])
            if restart.exitCode == 0 { continue }
            try await Shell.runThrowing("supervisorctl", ["start", product])
        }
    }

}
