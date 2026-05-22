import Vapor
import Mist

extension Deployer {

    func useUpdater(config: Configuration, deployerPhase: LiveState<DeployerPhase>) {
        let updater = Updater(app: app, config: config, deployerPhase: deployerPhase)
        self.updater = updater
        Task { await updater.startPolling() }
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

/// Owns the self-update lifecycle in the server. Spawns the detached update child for panel-initiated
/// updates and derives `isUpdating` from the cross-process **Update lock** so the panel reflects updates
/// regardless of who launched them — both panel clicks and user-typed `deployer update` in a shell.
/// See `docs/adr/0005-cli-server-state-channel.md`.
actor Updater {

    /// Set by `startUpdate` when we spawn a child; cleared by the polling Task once it observes the lock
    /// taken at least once and subsequently released, or after `Self.stickyBitTimeout` if the lock is
    /// never observed taken (child died before acquiring). Bridges the spawn-to-acquire window so the
    /// panel does not flicker `.updating → .ready → .updating`.
    private var stickyBit: Bool = false
    private var stickyBitSetAt: Date?
    private var stickyBitSawLockTaken: Bool = false

    /// Mirrors the latest observation from the polling Task.
    private var lockHeldObserved: Bool = false

    static let pollInterval: Duration = .seconds(2)
    static let stickyBitTimeout: TimeInterval = 5

    /// Derived: a self-update is in flight iff someone holds the lock OR we're in the spawn-to-acquire window.
    var isUpdating: Bool { lockHeldObserved || stickyBit }

    let app: Application
    let config: Configuration
    let deployerPhase: LiveState<DeployerPhase>

    init(app: Application, config: Configuration, deployerPhase: LiveState<DeployerPhase>) {
        self.app = app
        self.config = config
        self.deployerPhase = deployerPhase
    }

    /// Attempts to start a self-update from the panel. Refuses if any deploy is in flight or the update
    /// lock is already held (CLI-launched updates included). On success, sets the sticky bit and launches
    /// a detached child that survives this process's death. The child's lock acquisition is observed by
    /// the polling Task.
    func startUpdate() async -> StartUpdateResult {

        guard !isUpdating else { return .busy }

        let queueIsDeploying = await app.deployer.queue.isDeploying
        guard !queueIsDeploying else { return .busy }

        let executableURL: URL
        do { executableURL = try Configuration.getExecutableURL() }
        catch { return .failure(error.localizedDescription) }

        let installDirectory = executableURL.deletingLastPathComponent()
        if UpdateLock.isHeld(installDirectory: installDirectory) { return .busy }

        do {
            try spawnDetachedUpdate(executable: executableURL)
        } catch {
            return .failure(error.localizedDescription)
        }

        stickyBit = true
        stickyBitSetAt = .now
        stickyBitSawLockTaken = false
        await deployerPhase.set(.updating)

        return .started
    }

    /// Continuous polling loop: peeks the update lockfile every `pollInterval` and updates derived state.
    /// Runs for the lifetime of the process. Replaces the pre-ADR-0005 sentinel-file watcher.
    func startPolling() async {
        let installDirectory: URL
        do { installDirectory = try Configuration.getExecutableURL().deletingLastPathComponent() }
        catch { return app.logger.warning("Updater poll: could not resolve install directory: \(error.localizedDescription)") }

        while !Task.isCancelled {
            try? await Task.sleep(for: Self.pollInterval)
            await tick(installDirectory: installDirectory)
        }
    }

    /// One poll iteration. Folded out for testability and to keep `startPolling`'s loop body trivial.
    private func tick(installDirectory: URL) async {

        let nowHeld = UpdateLock.isHeld(installDirectory: installDirectory)
        let wasHeld = lockHeldObserved
        lockHeldObserved = nowHeld

        if stickyBit {
            if nowHeld {
                // Child has acquired — sticky bit no longer needs to lie on our behalf, but keep it set
                // until the child also releases, so we transition through observation rather than guess.
                stickyBitSawLockTaken = true
            } else if stickyBitSawLockTaken {
                // Child acquired then released — clear the bit, polling state owns truth from here.
                stickyBit = false
                stickyBitSetAt = nil
                stickyBitSawLockTaken = false
            } else if let setAt = stickyBitSetAt, Date.now.timeIntervalSince(setAt) > Self.stickyBitTimeout {
                // Child never acquired within the window — assume it died early, clear the bit.
                app.logger.warning("Updater poll: spawned child never acquired update lock within \(Self.stickyBitTimeout)s; clearing sticky bit.")
                stickyBit = false
                stickyBitSetAt = nil
                stickyBitSawLockTaken = false
            }
        }

        await broadcastPhaseIfChanged(wasHeld: wasHeld)
    }

    /// Reconciles `DeployerPhase` with derived state. Phase resolution: updating wins over deploying,
    /// matching `Panel.makePanelContext`'s priority. LiveState.set is a no-op if the value hasn't changed.
    private func broadcastPhaseIfChanged(wasHeld: Bool) async {
        
        let queueIsDeploying = await app.deployer.queue.isDeploying
        
        let resolved: DeployerPhase = switch (isUpdating, queueIsDeploying) {
            case (true, _): .updating
            case (_, true): .deploying
            case (false, false): .ready
        }
        
        await deployerPhase.set(resolved)
    }

    /// Launches the update child via the manager-appropriate cgroup-escape primitive.
    /// systemd: transient service via `systemd-run --user`. supervisor: `setsid` + background.
    /// The child is marked with `DEPLOYER_INTERNAL_UPDATE=1` so it skips the pre-acquire control-state
    /// query (which would otherwise see its own parent's `.updating` phase and refuse).
    private func spawnDetachedUpdate(executable: URL) throws {

        let binaryPath = executable.path.shellQuoted

        let command: String
        switch config.serviceManager {
            case .systemd:
                let unitName = "deployer-self-update-\(UUID().uuidString)"
                command = "systemd-run --user --collect --unit=\(unitName.shellQuoted) --setenv=DEPLOYER_INTERNAL_UPDATE=1 -- \(binaryPath) update"
            case .supervisor:
                command = "DEPLOYER_INTERNAL_UPDATE=1 setsid \(binaryPath) update </dev/null >/dev/null 2>&1 &"
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
