import Foundation
#if canImport(Musl)
import Musl
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// Small POSIX `flock` wrapper used by deployer domain locks.
final class FileLock {

    private var fd: Int32?

    private init(fd: Int32) {
        self.fd = fd
    }

    /// Non-destructive lock peek used for status rendering and race-aware busy checks.
    static func isHeld(path: String) -> Bool {

        let fd = open(path, O_CREAT | O_RDWR | O_CLOEXEC, 0o666)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        // Lockfiles may have been created by a different deployer user in an earlier invocation.
        _ = fchmod(fd, 0o666)

        if flock(fd, LOCK_EX | LOCK_NB) == 0 {
            _ = flock(fd, LOCK_UN)
            return false
        }

        return errno == EWOULDBLOCK
    }

    /// Acquires the lock without waiting so conflicting operator actions fail fast.
    static func acquire<LockError: Error>(
        path: String,
        busyError: LockError,
        failureError: (String, String) -> LockError
    ) throws -> FileLock {

        let fd = open(path, O_CREAT | O_RDWR | O_CLOEXEC, 0o666)
        guard fd >= 0 else { throw failureError(path, String(cString: strerror(errno))) }

        // Lockfiles may have been created by a different deployer user in an earlier invocation.
        _ = fchmod(fd, 0o666)

        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            let savedErrno = errno
            close(fd)
            if savedErrno == EWOULDBLOCK { throw busyError }
            throw failureError(path, String(cString: strerror(savedErrno)))
        }

        return FileLock(fd: fd)
    }

    /// Releases the held advisory lock before the lock object leaves scope.
    func release() {
        guard let fd else { return }
        _ = flock(fd, LOCK_UN)
        close(fd)
        self.fd = nil
    }

    deinit {
        release()
    }

}
