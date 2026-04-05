import SwiftUI
import Foundation

// MARK: - Log

private struct ReviewLogEntry: Codable {
    var taskId: String
    var action: String
    var timestamp: String
}

private func appendReviewLog(taskId: String, action: String) {
    let path = ThrawnPaths.opsFile("review-log.json")
    let entry = ReviewLogEntry(taskId: taskId, action: action, timestamp: ISO8601DateFormatter().string(from: Date()))
    var existing: [ReviewLogEntry] = []
    if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
       let decoded = try? JSONDecoder().decode([ReviewLogEntry].self, from: data) {
        existing = decoded
    }
    existing.append(entry)
    if let data = try? JSONEncoder().encode(existing) {
        try? data.write(to: URL(fileURLWithPath: path))
    }
}

// MARK: - Store

@MainActor
final class ReviewQueueStore: ObservableObject {
    @Published var reviewItems: [ParsedTask] = []
    @Published var handledIds: Set<String> = []
    @Published var isLoading = false

    func load() {
        isLoading = true
        Task {
            let path = ThrawnPaths.opsFile("TASK_BOARD.md")
            if let content = try? String(contentsOfFile: path, encoding: .utf8) {
                let all = parseTaskBoard(from: content)
                reviewItems = all.filter { $0.status.lowercased() == "review" }
            } else {
                reviewItems = []
            }
            isLoading = false
        }
    }

    func approve(_ task: ParsedTask) {
        appendReviewLog(taskId: task.id, action: "approve")
        handledIds.insert(task.id)
    }

    func requestRevision(_ task: ParsedTask) {
        appendReviewLog(taskId: task.id, action: "revision")
        handledIds.insert(task.id)
    }
}

// MARK: - View

struct ReviewQueueView: View {
    @StateObject private var store = ReviewQueueStore()

    var pending: [ParsedTask] { store.reviewItems.filter { !store.handledIds.contains($0.id) } }

    var body: some View {
        ZStack {
            Color.obsidian.ignoresSafeArea()
            RadialGradient(colors: [Color.chissDeep.opacity(0.40), Color.clear], center: .topLeading, startRadius: 0, endRadius: 600)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("REVIEW QUEUE")
                            .font(.system(size: 14, weight: .bold, design: .serif))
                            .tracking(3)
                            .foregroundColor(Color.chissPrimary)
                            .shadow(color: Color.chissPrimary.opacity(0.40), radius: 8)
                        Text("\(pending.count) pending review")
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
                        Image(systemName: "checklist.checked")
                            .font(.system(size: 36))
                            .foregroundColor(Color.chissPrimary.opacity(0.40))
                        Text("No items in review queue")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color.white.opacity(0.45))
                        Text("Tasks with Status: Review will appear here.")
                            .font(.system(size: 11))
                            .foregroundColor(Color.white.opacity(0.28))
                    }
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 14) {
                            ForEach(pending) { task in
                                ReviewItemCard(task: task, onApprove: { store.approve(task) }, onRevise: { store.requestRevision(task) })
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

// MARK: - Review Card

private struct ReviewItemCard: View {
    let task: ParsedTask
    let onApprove: () -> Void
    let onRevise: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.id)
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(1.5)
                        .foregroundColor(Color.chissPrimary.opacity(0.60))
                    Text(task.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.92))
                }
                Spacer()
                if !task.owner.isEmpty {
                    Text(task.owner)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color.chissPrimary)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(Color.chissDeep.opacity(0.55)).overlay(Capsule().stroke(Color.chissPrimary.opacity(0.30), lineWidth: 1)))
                }
            }

            if !task.deliverable.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Color.chissPrimary.opacity(0.70))
                    Text(task.deliverable)
                        .font(.system(size: 10.5))
                        .foregroundColor(Color.white.opacity(0.55))
                        .lineLimit(1)
                }
            }

            if !task.notes.isEmpty {
                Text(task.notes)
                    .font(.system(size: 10.5))
                    .foregroundColor(Color.white.opacity(0.45))
                    .lineLimit(2)
            }

            Divider().background(Color.chissPrimary.opacity(0.15))

            HStack(spacing: 10) {
                Button(action: onRevise) {
                    HStack(spacing: 5) {
                        Image(systemName: "pencil.circle").font(.system(size: 11, weight: .bold))
                        Text("Request Revision").font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(Color.white.opacity(0.75))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Capsule().fill(Color.white.opacity(0.07)).overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1)))
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: onApprove) {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 11, weight: .bold))
                        Text("Approve").font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(Color(red: 0.20, green: 0.58, blue: 0.38)).overlay(Capsule().stroke(Color(red: 0.35, green: 0.75, blue: 0.50).opacity(0.55), lineWidth: 1)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.obsidianMid)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color(red: 0.70, green: 0.55, blue: 0.90).opacity(0.28), lineWidth: 1))
        )
        .shadow(color: Color(red: 0.70, green: 0.55, blue: 0.90).opacity(0.12), radius: 8)
    }
}
