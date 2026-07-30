import Foundation

enum TaskCompletionPolicy {
    static func isDoneStatus(_ status: String) -> Bool {
        status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "done"
    }

    static func cleanEvidence(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func resolvedDeliverable(for task: ParsedTask) -> String? {
        cleanEvidence(task.deliverable) ?? discoverDeliverable(for: task.id)
    }

    static func discoverDeliverable(for taskId: String) -> String? {
        manifestEvidence(for: taskId) ?? fileEvidence(for: taskId)
    }

    private static func manifestEvidence(for taskId: String) -> String? {
        let manifestURL = ThrawnPaths.appSupportDir
            .appendingPathComponent("workspace/deliverables/manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let json = try? JSONSerialization.jsonObject(with: data) else { return nil }

        let items: [[String: Any]]
        if let dict = json as? [String: Any],
           let deliverables = dict["deliverables"] as? [[String: Any]] {
            items = deliverables
        } else if let array = json as? [[String: Any]] {
            items = array
        } else {
            return nil
        }

        let matches = items.filter { item in
            let itemTaskId = (item["task_id"] as? String)
                ?? (item["taskId"] as? String)
                ?? (item["ticket_id"] as? String)
                ?? (item["ticketId"] as? String)
            return itemTaskId?.caseInsensitiveCompare(taskId) == .orderedSame
        }

        for item in matches {
            for key in ["file_path", "filePath", "path", "evidence_path", "evidencePath", "url"] {
                if let evidence = cleanEvidence(item[key] as? String) {
                    return normalizedWorkspacePath(preferredDeliverablePath(evidence))
                }
            }
        }

        return nil
    }

    private static func fileEvidence(for taskId: String) -> String? {
        let deliverablesDir = ThrawnPaths.appSupportDir
            .appendingPathComponent("workspace/deliverables", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: deliverablesDir,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        let prefix = taskId.lowercased()
        let matches = enumerator.compactMap { entry -> URL? in
            guard let url = entry as? URL else { return nil }
            let name = url.lastPathComponent.lowercased()
            guard name != "manifest.json" else { return nil }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else { return nil }
            let relative = workspaceRelativePath(for: url).lowercased()
            guard relative.contains("/deliverables/\(prefix)/") || name.hasPrefix(prefix) else { return nil }
            return url
        }
        .sorted { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhsDate > rhsDate
        }

        guard let newest = matches.first else { return nil }
        return workspaceRelativePath(for: newest)
    }

    private static func workspaceRelativePath(for url: URL) -> String {
        let workspaceURL = ThrawnPaths.appSupportDir.appendingPathComponent("workspace", isDirectory: true)
        let workspacePath = workspaceURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        let prefix = workspacePath.hasSuffix("/") ? workspacePath : workspacePath + "/"
        if path.hasPrefix(prefix) {
            return "workspace/" + String(path.dropFirst(prefix.count))
        }
        return path
    }

    private static func preferredDeliverablePath(_ value: String) -> String {
        guard !value.hasPrefix("http://"), !value.hasPrefix("https://") else { return value }
        let url = absoluteURL(for: value)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return value }

        for name in ["index.html", "visual-board.html", "report.html", "board.html", "report.md", "board.md"] {
            let candidate = url.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return workspaceRelativePath(for: candidate)
            }
        }
        return value
    }

    private static func absoluteURL(for value: String) -> URL {
        if value.hasPrefix("/") { return URL(fileURLWithPath: value) }
        if value.hasPrefix("workspace/") {
            return ThrawnPaths.appSupportDir.appendingPathComponent(value)
        }
        return ThrawnPaths.appSupportDir.appendingPathComponent("workspace").appendingPathComponent(value)
    }

    private static func normalizedWorkspacePath(_ value: String) -> String {
        if value.hasPrefix("/") || value.hasPrefix("workspace/") || value.hasPrefix("http://") || value.hasPrefix("https://") {
            return value
        }
        return "workspace/" + value
    }
}
