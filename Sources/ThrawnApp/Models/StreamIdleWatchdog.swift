import Foundation

// MARK: - Stream Idle Watchdog
//
// Detects stalled streaming responses. Each token / SSE line received calls
// `touch()` to refresh the last-byte timestamp. A separate Task polls every
// few seconds and, if the stream has been idle for longer than `timeoutSeconds`,
// calls the cancel handler so the streaming caller can abort.
//
// Why this exists: the underlying URLSession request has a 600-second timeout,
// but that's an end-to-end timeout — if the server sends headers and one byte
// then stalls, we'd wait the full 10 minutes. The idle watchdog catches
// "the connection is technically open but nothing is coming through" much
// sooner, which is what users actually experience.
//
// Reliability rule: a stalled stream is a silent failure. The watchdog
// guarantees the stream either makes progress or terminates with a logged
// error — never sits forever.

/// Shared mutable state across the producer (touch() on each byte) and the
/// consumer (the polling Task). Actor isolation keeps it race-free without
/// requiring locks at every call site.
actor StreamIdleWatchdog {
    private var lastByteAt: Date
    private var stopped: Bool = false
    private let timeoutSeconds: TimeInterval

    init(timeoutSeconds: TimeInterval) {
        self.lastByteAt = Date()
        self.timeoutSeconds = timeoutSeconds
    }

    /// Refresh the last-byte timestamp. Call this on every chunk/line received.
    func touch() {
        guard !stopped else { return }
        lastByteAt = Date()
    }

    /// Mark the watchdog as stopped — `isStalled` will always return false
    /// after this. Called when the stream completes normally or is cancelled.
    func stop() {
        stopped = true
    }

    /// True if the stream has not received a byte in `timeoutSeconds`.
    /// Returns false if the watchdog has been stopped.
    func isStalled() -> Bool {
        if stopped { return false }
        return Date().timeIntervalSince(lastByteAt) > timeoutSeconds
    }

    /// Seconds since the last byte was received.
    func secondsIdle() -> TimeInterval {
        Date().timeIntervalSince(lastByteAt)
    }
}

// MARK: - Polling Task helper

/// Spawn a Task that polls the watchdog every `pollIntervalSeconds` and
/// calls `onStall` if the stream goes idle. Returns the polling Task so
/// the caller can cancel it on stream completion. The handler is called
/// at most once per watchdog instance — subsequent stalls are ignored.
func startStreamIdleWatchdog(
    _ watchdog: StreamIdleWatchdog,
    pollIntervalSeconds: Double = 2.0,
    onStall: @escaping @Sendable (TimeInterval) -> Void
) -> Task<Void, Never> {
    return Task {
        var fired = false
        let pollNs = UInt64(pollIntervalSeconds * 1_000_000_000)
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: pollNs)
            if Task.isCancelled { return }
            let stalled = await watchdog.isStalled()
            if stalled, !fired {
                fired = true
                let idle = await watchdog.secondsIdle()
                onStall(idle)
                return
            }
        }
    }
}
