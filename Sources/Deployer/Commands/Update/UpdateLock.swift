import Foundation
#if canImport(Musl)
import Musl
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// Cross-process advisory lock that guarantees only one `deployer update` pipeline runs at a time on a host.
/// Held for the lifetime of the lock value; the kernel releases the underlying `flock(2)` automatically on
/// process exit, so a crashed updater never leaves a stale lock behind.
final class UpdateLock {

    private let fd: Int32
    private let path: String

    private init(fd: Int32, path: String) {
        self.fd = fd
        self.path = path
    }

    /// Opens (or creates) the lockfile in `installDirectory` and acquires an exclusive non-blocking flock.
    /// Throws `.anotherUpdateInProgress` if another updater holds it, or `.lockFailed` on unexpected I/O errors.
    static func acquire(installDirectory: URL) throws -> UpdateLock {
        let path = installDirectory.appendingPathComponent(".deployer-update.lock").path

        let fd = open(path, O_CREAT | O_RDWR | O_CLOEXEC, 0o666)
        guard fd >= 0 else {
            throw UpdateCommand.Error.lockFailed(path, String(cString: strerror(errno)))
        }

        // Lockfile may already exist with restrictive perms from an older root-only run; widen so the panel-spawned
        // child running as the service user can also acquire the lock on subsequent invocations.
        _ = fchmod(fd, 0o666)

        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            let savedErrno = errno
            close(fd)
            if savedErrno == EWOULDBLOCK { throw UpdateCommand.Error.anotherUpdateInProgress }
            throw UpdateCommand.Error.lockFailed(path, String(cString: strerror(savedErrno)))
        }

        return UpdateLock(fd: fd, path: path)
    }

    deinit {
        close(fd)
    }

}
