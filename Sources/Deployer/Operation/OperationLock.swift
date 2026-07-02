import Foundation

/// Cross-process lock that serializes mutating deployer operations across the panel and CLI.
///
/// Acquire the lock by calling `acquire()` before starting an operation. The returned lock must be kept
/// alive in memory for the exact duration of the operation. The lock is safely released by `deinit` once it
/// goes out-of-scope, or explicitly by calling `release()`.
final class OperationLock: @unchecked Sendable {

    private let lock: FileLock

    private init(lock: FileLock) {
        self.lock = lock
    }
    
    /// Computes the filesystem path of the lock file for the current deployer installation.
    private static func lockPath() throws -> String {
        try Configuration.getExecutableURL()
            .deletingLastPathComponent()
            .appendingPathComponent(".deployer-operation.lock")
            .path
    }

    /// Non-destructive lock peek used for status rendering and race-aware busy checks.
    static func isHeld() -> Bool {

        guard let path = try? lockPath() else { return false }
        return FileLock.isHeld(path: path)
    }

    /// Acquires the operation lock without waiting so conflicting operator actions fail fast.
    static func acquire() throws -> OperationLock {

        let path = try lockPath()
        let lock = try FileLock.acquire(
            path: path,
            busyError: OperationError.anotherOperationInProgress,
            failureError: OperationError.lockFailed
        )
        return OperationLock(lock: lock)
    }

    /// Releases the held advisory lock before the lock object leaves scope.
    func release() {
        lock.release()
    }

    deinit {
        release()
    }

}
