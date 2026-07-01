import Foundation
#if canImport(Musl)
import Musl
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// Cross-process advisory lock that serializes mutating deployer operations across the panel and CLI.
final class OperationLock: @unchecked Sendable {

    private var fd: Int32?

    private init(fd: Int32) {
        self.fd = fd
    }
    
    /// Computes the filesystem path of the lock file within the deployment installation directory.
    static func lockPath(installDirectory: URL) -> String {
        installDirectory.appendingPathComponent(".deployer-operation.lock").path
    }

    /// Non-destructive lock peek used for status rendering and race-aware busy checks.
    static func isHeld(installDirectory: URL) -> Bool {

        let path = lockPath(installDirectory: installDirectory)

        let fd = open(path, O_CREAT | O_RDWR | O_CLOEXEC, 0o666)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        _ = fchmod(fd, 0o666)

        if flock(fd, LOCK_EX | LOCK_NB) == 0 {
            _ = flock(fd, LOCK_UN)
            return false
        }

        return errno == EWOULDBLOCK
    }

    /// Acquires the operation lock without waiting so conflicting operator actions fail fast.
    static func acquire(installDirectory: URL) throws -> OperationLock {

        let path = lockPath(installDirectory: installDirectory)

        let fd = open(path, O_CREAT | O_RDWR | O_CLOEXEC, 0o666)
        guard fd >= 0 else {
            throw OperationError.lockFailed(path, String(cString: strerror(errno)))
        }

        _ = fchmod(fd, 0o666)

        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            let savedErrno = errno
            close(fd)
            if savedErrno == EWOULDBLOCK { throw OperationError.anotherOperationInProgress }
            throw OperationError.lockFailed(path, String(cString: strerror(savedErrno)))
        }

        return OperationLock(fd: fd)
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
