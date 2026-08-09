import Foundation

/// Thread-safe byte accumulator for subprocess pipes: readability handlers
/// fire on a background queue while termination handlers read the result.
final class LockedBuffer: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    func tailText(_ maxBytes: Int) -> String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: data.suffix(maxBytes), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
