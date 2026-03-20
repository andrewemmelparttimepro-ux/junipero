import SwiftUI

enum TaskColumn: String, CaseIterable, Identifiable {
    case todo = "To Do"
    case inProgress = "In Progress"
    case done = "Done"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .todo: return "circle"
        case .inProgress: return "arrow.triangle.2.circlepath"
        case .done: return "checkmark.circle.fill"
        }
    }
}

struct TasksView: View {
    var body: some View {
        VStack(spacing: 0) {
            header

            Rectangle()
                .fill(JuniperoTheme.divider)
                .frame(height: 1)

            kanbanBoard
        }
        .background(JuniperoTheme.backgroundPrimary)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Tasks")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(JuniperoTheme.textPrimary)

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Kanban Board

    private var kanbanBoard: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(TaskColumn.allCases) { column in
                taskColumn(column)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func taskColumn(_ column: TaskColumn) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: column.icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(JuniperoTheme.copper)

                Text(column.rawValue)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(JuniperoTheme.copper)

                Spacer()

                Text("0")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(JuniperoTheme.textTertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(JuniperoTheme.backgroundElevated)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(JuniperoTheme.backgroundSecondary)
            .clipShape(
                RoundedRectangle(cornerRadius: 10)
                    .offset(y: -5)
            )

            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "tray")
                    .font(.system(size: 24, weight: .light))
                    .foregroundColor(JuniperoTheme.textTertiary.opacity(0.5))

                Text("No tasks")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(JuniperoTheme.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(JuniperoTheme.backgroundSurface.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(JuniperoTheme.divider, lineWidth: 1)
        )
    }
}

// MARK: - Empty State Overlay

private struct TasksEmptyOverlay: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("No tasks yet.")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(JuniperoTheme.textSecondary)

            Text("Tasks created during conversations with Hermes will appear here.")
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(JuniperoTheme.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
    }
}
