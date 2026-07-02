import Foundation

/// Cross-process lock that serializes deployer self-update operations across the panel and CLI.
///
/// Acquire the lock by calling `acquire()` before starting an update. The returned lock must be kept
/// alive in memory for the exact duration of the update. The lock is safely released by `deinit` once it
/// goes out-of-scope, or explicitly by calling `release()`.
final class UpdateLock {

    private let lock: FileLock

    /// Computes the filesystem path of the lock file for the current deployer installation.
    private static func lockPath() throws -> String {
        try Configuration.getExecutableURL()
            .deletingLastPathComponent()
            .appendingPathComponent(".deployer-update.lock")
            .path
    }

    private init(lock: FileLock) {
        self.lock = lock
    }

    /// Non-destructive lock peek used for status rendering and race-aware busy checks.
    static func isHeld() -> Bool {
        
        guard let path = try? lockPath() else { return false }
        return FileLock.isHeld(path: path)
    }

    /// Acquires the update lock without waiting so conflicting operator actions fail fast.
    static func acquire() throws -> UpdateLock {
        
        let path = try lockPath()
        let lock = try FileLock.acquire(
            path: path,
            busyError: UpdateCommand.Error.anotherUpdateInProgress,
            failureError: UpdateCommand.Error.lockFailed
        )
        return UpdateLock(lock: lock)
    }

    /// Releases the held advisory lock before the lock object leaves scope.
    func release() {
        lock.release()
    }

    deinit {
        release()
    }

}
