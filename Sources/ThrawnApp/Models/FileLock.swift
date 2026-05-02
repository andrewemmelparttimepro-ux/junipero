import Foundation

// MARK: - File Lock
//
// POSIX advisory lock wrapper for cross-process mutual exclusion. Used to
// guard TASK_BOARD.md so the dispatcher's read-modify-write cycle is safe
// against:
//   • External editors (vim/emacs respect flock)
//   • A second Thrawn instance running simultaneously
//   • Future helper processes that need to touch the board
//
// The lock is held on a sentinel `.lock` file rather than the data file
// itself, because we need atomic writes (via temp-file-then-rename) to
// prevent partial-file corruption — and rename creates a new inode that
// breaks any flock on the original. The lock-file pattern decouples the
// two concerns: rename gives atomicity, flock gives exclusion.
//
// Reliability rule: a lock acquisition that fails is logged and treated
// as "proceed without lock" rather than blocking forever. Better to lose
// strict mutual exclusion in a degraded state than to deadlock.

/// Acquire a POSIX exclusive flock on a sentinel lock file, run a closure,
/// then release the lock. If the lock can't be acquired within `timeout`
/// seconds, the closure runs anyway with a logged warning — reliability
/// over perfect correctness.
struct FileLock {
    /// Default timeout for acquiring the lock. The dispatcher's batch
    /// processing should never hold the lock more than a few hundred ms,
    /// so 10 seconds is a generous ceiling.
    static let defaultTimeoutSeconds: Double = 10

    /// Run `body` while holding an exclusive flock on `lockURL`. The lock
    /// file is created if it doesn't exist. Always releases the lock,
    /// even if `body` throws.
    ///
    /// - Parameters:
    ///   - lockURL: Path to the lock file (typically `<datafile>.lock`).
    ///   - timeoutSeconds: How long to wait for the lock before giving up.
    ///   - source: Subsystem name for FlightRecorder logs.
    ///   - body: The critical-section work.
    static func withLock<T>(
        at lockURL: URL,
        timeoutSeconds: Double = defaultTimeoutSeconds,
        source: String,
        _ body: () throws -> T
    ) rethrows -> T {
        let fd = openLockFile(at: lockURL, source: source)

        // If we couldn't even open the lock file, run the body anyway —
        // we'd rather lose strict exclusion than fail the whole operation.
        // The error is already logged by openLockFile.
        guard fd >= 0 else {
            return try body()
        }
        defer { close(fd) }

        let acquired = acquireExclusive(fd: fd, timeoutSeconds: timeoutSeconds)
        if !acquired {
            FlightRecorder.logError(
                source: source,
                message: "Could not acquire flock on \(lockURL.lastPathComponent) within \(Int(timeoutSeconds))s — proceeding without lock. Another writer may be active."
            )
        }
        defer {
            if acquired { _ = flock(fd, LOCK_UN) }
        }

        return try body()
    }

    // MARK: - Internals

    /// Open (or create) the lock file with the right flags for flock().
    /// Returns -1 if open failed; logs the error.
    private static func openLockFile(at url: URL, source: String) -> Int32 {
        // Make sure the parent dir exists before we try to open the lock.
        let parent = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parent.path) {
            do {
                try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            } catch {
                FlightRecorder.logError(
                    source: source,
                    message: "Could not create lock dir \(parent.path): \(error.localizedDescription)"
                )
                return -1
            }
        }

        // O_RDWR | O_CREAT — write open so flock works; create on demand.
        // Mode 0o644 — owner read/write, group/other read.
        let path = url.path
        let fd = path.withCString { cPath in
            open(cPath, O_RDWR | O_CREAT, 0o644)
        }
        if fd < 0 {
            let errMsg = String(cString: strerror(errno))
            FlightRecorder.logError(
                source: source,
                message: "open(\(url.lastPathComponent)) for flock failed: \(errMsg)"
            )
        }
        return fd
    }

    /// Try to acquire LOCK_EX. Polls in 50 ms intervals until success or
    /// timeout. Uses `LOCK_EX | LOCK_NB` so we never block the thread.
    private static func acquireExclusive(fd: Int32, timeoutSeconds: Double) -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        let pollInterval: useconds_t = 50_000  // 50 ms

        while Date() < deadline {
            if flock(fd, LOCK_EX | LOCK_NB) == 0 {
                return true
            }
            // EWOULDBLOCK = held by someone else; keep waiting.
            // Anything else = real error; bail.
            if errno != EWOULDBLOCK {
                return false
            }
            usleep(pollInterval)
        }
        return false
    }
}
