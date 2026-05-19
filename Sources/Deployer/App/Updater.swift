import Vapor
import Mist

extension Deployer {

    func useUpdater(config: Configuration, deployerPhase: LiveState<DeployerPhase>) {
        updater = Updater(app: app, config: config, deployerPhase: deployerPhase)
    }

    var updater: Updater {
        get {
            if let updater = app.storage[UpdaterKey.self] { return updater }
            fatalError("Updater not initialized.")
        }
        nonmutating set {
            app.storage[UpdaterKey.self] = newValue
        }
    }

    private struct UpdaterKey: StorageKey { typealias Value = Updater }

}

/// Owns the self-update lock and spawns the detached `deployer update` child.
/// Mutual exclusion with `Queue.isDeploying` is best-effort (see CONTEXT.md and docs/adr/0001).
actor Updater {

    private(set) var isUpdating: Bool = false

    let app: Application
    let config: Configuration
    let deployerPhase: LiveState<DeployerPhase>

    init(app: Application, config: Configuration, deployerPhase: LiveState<DeployerPhase>) {
        self.app = app
        self.config = config
        self.deployerPhase = deployerPhase
    }

    /// Attempts to start a self-update. Refuses if any deploy is in flight or another update is running.
    /// On success, sets `.updating` state and launches a detached child that survives this process's death.
    func startUpdate() async -> StartUpdateResult {

        guard !isUpdating else { return .busy }

        let queueIsDeploying = await app.deployer.queue.isDeploying
        guard !queueIsDeploying else { return .busy }

        let executableURL: URL
        do { executableURL = try Configuration.getExecutableURL() }
        catch { return .failure(error.localizedDescription) }

        let installDirectory = executableURL.deletingLastPathComponent()
        let sentinelURL = installDirectory.appendingPathComponent(".deployer-self-update.sentinel")
        try? FileManager.default.removeItem(at: sentinelURL)

        do {
            try spawnDetachedUpdate(executable: executableURL, sentinelURL: sentinelURL)
        } catch {
            return .failure(error.localizedDescription)
        }

        isUpdating = true
        await deployerPhase.set(.updating)

        Task { await watchForCompletion(sentinelURL: sentinelURL) }

        return .started
    }

    /// Polls for the completion sentinel written by the child on every exit (success or failure).
    /// If the child kills the parent before writing (the late-success / late-failure-rollback paths),
    /// this Task dies with the process; the new boot starts fresh with `isUpdating = false`.
    private func watchForCompletion(sentinelURL: URL) async {

        let fileManager = FileManager.default

        while isUpdating {
            try? await Task.sleep(for: .seconds(2))

            guard fileManager.fileExists(atPath: sentinelURL.path) else { continue }

            try? fileManager.removeItem(at: sentinelURL)
            isUpdating = false
            await deployerPhase.set(.ready)
            return
        }
    }

    /// Launches the update child via the manager-appropriate cgroup-escape primitive.
    /// systemd: transient service via `systemd-run --user`. supervisor: `setsid` + background.
    private func spawnDetachedUpdate(executable: URL, sentinelURL: URL) throws {

        let binaryPath = executable.path.shellQuoted
        let sentinelPath = sentinelURL.path.shellQuoted

        let command: String
        switch config.serviceManager {
            case .systemd:
                let unitName = "deployer-self-update-\(UUID().uuidString)"
                command = "systemd-run --user --collect --unit=\(unitName.shellQuoted) --setenv=DEPLOYER_COMPLETION_SENTINEL=\(sentinelPath) -- \(binaryPath) update"
            case .supervisor:
                command = "DEPLOYER_COMPLETION_SENTINEL=\(sentinelPath) setsid \(binaryPath) update </dev/null >/dev/null 2>&1 &"
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["bash", "-c", command]
        try process.run()
    }

    enum StartUpdateResult: Sendable {

        case started
        case busy
        case failure(String)

    }

}
