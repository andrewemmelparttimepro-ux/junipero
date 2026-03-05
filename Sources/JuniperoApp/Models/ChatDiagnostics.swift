import Foundation

actor ChatDiagnostics {
    static let shared = ChatDiagnostics()

    private let logURL: URL
    private let maxBytes = 1_000_000

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".junipero", isDirectory: true)
        self.logURL = dir.appendingPathComponent("chat.log")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func log(_ message: String) async {
        let line = "[\(Self.isoNow())] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if !FileManager.default.fileExists(atPath: logURL.path) {
            try? data.write(to: logURL, options: .atomic)
            return
        }

        if let attrs = try? FileManager.default.attributesOfItem(atPath: logURL.path),
           let size = attrs[.size] as? NSNumber,
           size.intValue > maxBytes
        {
            let rotated = logURL.deletingLastPathComponent().appendingPathComponent("chat.log.1")
            try? FileManager.default.removeItem(at: rotated)
            try? FileManager.default.moveItem(at: logURL, to: rotated)
            try? data.write(to: logURL, options: .atomic)
            return
        }

        if let fh = try? FileHandle(forWritingTo: logURL) {
            _ = try? fh.seekToEnd()
            try? fh.write(contentsOf: data)
            try? fh.close()
        }
    }

    private static func isoNow() -> String {
        let f = ISO8601DateFormatter()
        return f.string(from: Date())
    }
}
