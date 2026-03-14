import SwiftUI
import Foundation

// MARK: - Model

struct ApprovalItem: Identifiable {
    let id: String
    var title: String
    var requestedBy: String
    var description: String
    var impact: String
}

// MARK: - Log

private struct ApprovalLogEntry: Codable {
    var approvalId: String
    var action: String
    var timestamp: String
}

private func appendApprovalLog(approvalId: String, action: String) {
    let path = "/Users/crustacean/.openclaw/workspace/ops/approval-log.json"
    let entry = ApprovalLogEntry(approvalId: approvalId, action: action, timestamp: ISO8601DateFormatter().string(from: Date()))
    var existing: [ApprovalLogEntry] = []
    if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
       let decoded = try? JSONDecoder().decode([ApprovalLogEntry].self, from: data) {
        existing = decoded
    }
    existing.append(entry)
    if let data = try? JSONEncoder().encode(existing) {
        try? data.write(to: URL(fileURLWithPath: path))
    }
}

// MARK: - Parser

private func parseApprovalQueue(from text: String) -> [ApprovalItem] {
    var items: [ApprovalItem] = []
    let lines = text.components(separatedBy: "\n")
    var i = 0

    while i < lines.count {
        let line = lines[i]
        if line.hasPrefix("### APPROVAL-") {
            let itemId = String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            var fields: [String: String] = [:]
            i += 1
            while i < lines.count && !lines[i].hasPrefix("### ") {
                let l = lines[i]
                if l.hasPrefix("- "), let colon = l.range(of: ": ") {
                    let key = String(l[l.index(l.startIndex, offsetBy: 2)..<colon.lowerBound]).trimmingCharacters(in: .whitespaces)
                    let value = String(l[colon.upperBound...]).trimmingCharacters(in: .whitespaces)
                    fields[key] = value
                }
                i += 1
            }
            items.append(ApprovalItem(
                id: itemId,
                title: fields["Title"] ?? itemId,
                requestedBy: fields["Requested by"] ?? "",
                description: fields["Description"] ?? "",
                impact: fields["Impact"] ?? ""
            ))
        } else {
            i += 1
        }
    }
    return items
}

// MARK: - Store

@MainActor
final class ApprovalsStore: ObservableObject {
    @Published var items: [ApprovalItem] = []
    @Published var handledIds: Set<String> = []
    @Published var isLoading = false

    func load() {
        isLoading = true
        Task {
            let path = "/Users/crustacean/.openclaw/workspace/ops/APPROVALS_QUEUE.md"
            if let content = try? String(contentsOfFile: path, encoding: .utf8) {
                items = parseApprovalQueue(from: content)
            } else {
                items = []
            }
            isLoading = false
        }
    }

    func approve(_ item: ApprovalItem) {
        appendApprovalLog(approvalId: item.id, action: "approve")
        handledIds.insert(item.id)
    }

    func deny(_ item: ApprovalItem) {
        appendApprovalLog(approvalId: item.id, action: "deny")
        handledIds.insert(item.id)
    }
}

// MARK: - View

struct ApprovalsView: View {
    @StateObject private var store = ApprovalsStore()

    var pending: [ApprovalItem] { store.items.filter { !store.handledIds.contains($0.id) } }

    var body: some View {
        ZStack {
            Color.obsidian.ignoresSafeArea()
            RadialGradient(colors: [Color.chissDeep.opacity(0.35), Color.clear], center: .topLeading, startRadius: 0, endRadius: 600)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("APPROVALS")
                            .font(.system(size: 14, weight: .bold, design: .serif))
                            .tracking(3)
                            .foregroundColor(Color.chissPrimary)
                            .shadow(color: Color.chissPrimary.opacity(0.40), radius: 8)
                        Text("\(pending.count) pending decision\(pending.count == 1 ? "" : "s")")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.40))
                    }
                    Spacer()
                    if store.isLoading {
                        ProgressView().progressViewStyle(.circular).scaleEffect(0.65).tint(Color.chissPrimary)
                    }
                    Button { store.load() } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.clockwise").font(.system(size: 10, weight: .bold))
                            Text("Reload").font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(Color.chissPrimary)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(Color.chissDeep.opacity(0.55)).overlay(Capsule().stroke(Color.chissPrimary.opacity(0.35), lineWidth: 1)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24).padding(.vertical, 14)
                .background(Color.obsidianMid.opacity(0.92))
                .overlay(alignment: .bottom) { Rectangle().fill(Color.chissPrimary.opacity(0.12)).frame(height: 1) }

                if pending.isEmpty {
                    Spacer()
                    VStack(spacing: 10) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 36))
                            .foregroundColor(Color.chissPrimary.opacity(0.40))
                        Text("No pending approvals")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color.white.opacity(0.45))
                        Text("Items from APPROVALS_QUEUE.md will surface here.")
                            .font(.system(size: 11))
                            .foregroundColor(Color.white.opacity(0.28))
                    }
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 14) {
                            ForEach(pending) { item in
                                ApprovalCard(item: item, onApprove: { store.approve(item) }, onDeny: { store.deny(item) })
                            }
                        }
                        .padding(.horizontal, 24).padding(.vertical, 18)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear { store.load() }
    }
}

// MARK: - Approval Card

private struct ApprovalCard: View {
    let item: ApprovalItem
    let onApprove: () -> Void
    let onDeny: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.id)
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(1.5)
                        .foregroundColor(Color.chissPrimary.opacity(0.60))
                    Text(item.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.92))
                }
                Spacer()
                if !item.requestedBy.isEmpty {
                    Text(item.requestedBy)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color.chissPrimary)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(Color.chissDeep.opacity(0.55)).overlay(Capsule().stroke(Color.chissPrimary.opacity(0.30), lineWidth: 1)))
                }
            }

            if !item.description.isEmpty {
                Text(item.description)
                    .font(.system(size: 11))
                    .foregroundColor(Color.white.opacity(0.55))
                    .lineLimit(3)
            }

            if !item.impact.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 9))
                        .foregroundColor(Color(red: 0.95, green: 0.70, blue: 0.20))
                    Text(item.impact)
                        .font(.system(size: 10.5))
                        .foregroundColor(Color(red: 0.95, green: 0.70, blue: 0.20).opacity(0.85))
                        .lineLimit(2)
                }
            }

            Divider().background(Color.chissPrimary.opacity(0.15))

            HStack(spacing: 10) {
                Button(action: onDeny) {
                    HStack(spacing: 5) {
                        Image(systemName: "xmark.circle").font(.system(size: 11, weight: .bold))
                        Text("Deny").font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(Color.sithGlow)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Capsule().fill(Color.sithRed.opacity(0.12)).overlay(Capsule().stroke(Color.sithGlow.opacity(0.35), lineWidth: 1)))
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: onApprove) {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.shield.fill").font(.system(size: 11, weight: .bold))
                        Text("Approve").font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(Color.chissDeep).overlay(Capsule().stroke(Color.chissPrimary.opacity(0.55), lineWidth: 1)))
                    .shadow(color: Color.chissPrimary.opacity(0.25), radius: 8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.obsidianMid)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.chissPrimary.opacity(0.22), lineWidth: 1))
        )
    }
}
