import Foundation

/// Setup/teardown operations for systemd user units.
struct SystemdConfigurator: ServiceConfigurator {

    let shell: SystemShell
    let paths: SystemPaths

    private var unitDirectory: String { "\(paths.serviceHome)/.config/systemd/user" }
    private var serviceUser: String { shell.context.serviceUser }

    func isRunning(_ service: String) async -> Bool {
        let output = try? await shell.runUserSystemctl("is-active", ["\(service).service"])
        return output?.trimmed == "active"
    }

    func disable(_ products: [String]) async {
        let units = products.map { "\($0).service" }
        _ = try? await shell.runUserSystemctl("disable", ["--now"] + units)
    }

    func removeConfigs(for products: [String]) async {
        for product in products {
            try? SystemFileSystem.removeIfPresent("\(unitDirectory)/\(product).service")
        }
        _ = try? await shell.runUserSystemctl("daemon-reload")
    }

    func enableAndStart(_ products: [String]) async throws {
        let uid = try await shell.context.requireServiceUserUID()

        try await Shell.runThrowing("loginctl", ["enable-linger", serviceUser])
        await Shell.run("systemctl", ["start", "user@\(uid).service"])
        try await SystemShell.waitForUserBus(uid: uid)
        try await shell.runUserSystemctl("daemon-reload")

        let units = products.map { "\($0).service" }
        try await shell.runUserSystemctl("enable", units)
        try await shell.runUserSystemctl("restart", units)
    }

}
