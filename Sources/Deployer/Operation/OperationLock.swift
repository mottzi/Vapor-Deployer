import Foundation
#if canImport(Musl)
import Musl
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// Cross-process lock that serializes mutating deployer operations across the panel and CLI.
///
/// Acquire the lock by calling `acquire()` before starting an operation. The returned lock must be kept
/// alive in memory for the exact duration of the operation. The lock is safely released by `deinit` once it
/// goes out-of-scope, or explicitly by calling `release()`.
final class OperationLock: @unchecked Sendable {

    /// The open file descriptor holding the OS-level lock. `nil` if the lock has been released.
    private var fd: Int32?

    private init(fd: Int32) {
        self.fd = fd
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

        // resolve lockfile path
        guard let path = try? lockPath() else { return false }
        // open or create file descriptor
        let fd = open(path, O_CREAT | O_RDWR | O_CLOEXEC, 0o666)
        // assume not held if file can't be opened
        guard fd >= 0 else { return false }
        // always close file on exit
        defer { close(fd) }
        
        // widen permissions for cross-user access
        _ = fchmod(fd, 0o666)

        if flock(fd, LOCK_EX | LOCK_NB) == 0 {
            // lock was free, release immediately
            _ = flock(fd, LOCK_UN)
            return false
        }

        // check if denied due to another process holding lock
        return errno == EWOULDBLOCK
    }

    /// Acquires the operation lock without waiting so conflicting operator actions fail fast.
    static func acquire() throws -> OperationLock {

        let path = try lockPath()
        let fd = open(path, O_CREAT | O_RDWR | O_CLOEXEC, 0o666)
        guard fd >= 0 else { throw OperationError.lockFailed(path, String(cString: strerror(errno))) }
        _ = fchmod(fd, 0o666)

        // try exclusive, non-blocking lock
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            // can't take lock, save errno and close file
            let savedErrno = errno
            close(fd)
            // lock is already taken
            if savedErrno == EWOULDBLOCK { throw OperationError.anotherOperationInProgress }
            // lock failure
            throw OperationError.lockFailed(path, String(cString: strerror(savedErrno)))
        }

        // lock acquired
        return OperationLock(fd: fd)
    }

    /// Releases the held advisory lock before the lock object leaves scope.
    func release() {
        // file already released
        guard let fd else { return }
        // unlock and close file
        _ = flock(fd, LOCK_UN)
        close(fd)
        // prevent double release by deinit
        self.fd = nil
    }

    deinit {
        release()
    }

}
