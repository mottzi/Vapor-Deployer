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
/// process exit, so a crashed updater never leaves a stale lock behind. After ADR 0005 the lock also serves
/// as the cross-process source of truth for "an update is in flight" — both the `Updater` (panel) and
/// `Queue.start` (deploy preflight) peek it via `isHeld(installDirectory:)`.
final class UpdateLock {

    private let fd: Int32
    private let path: String

    static func lockPath(installDirectory: URL) -> String {
        installDirectory.appendingPathComponent(".deployer-update.lock").path
    }

    private init(fd: Int32, path: String) {
        self.fd = fd
        self.path = path
    }

    /// Non-destructive peek: tries to acquire the lock exclusively, then releases it immediately if it succeeded.
    /// Returns `true` if some other process holds the lock right now, `false` if it's free (or if we couldn't
    /// even open the file, which is treated as "not held" since the absence of a lockfile means no updater).
    /// Tiny race: during the few microseconds we briefly hold the lock to release it, a concurrent acquirer
    /// would see EWOULDBLOCK. Acceptable — `acquire` callers always retry by failing fast to the user.
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

    /// Opens (or creates) the lockfile in `installDirectory` and acquires an exclusive non-blocking flock.
    /// Throws `.anotherUpdateInProgress` if another updater holds it, or `.lockFailed` on unexpected I/O errors.
    static func acquire(installDirectory: URL) throws -> UpdateLock {
        let path = lockPath(installDirectory: installDirectory)

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
