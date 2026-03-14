import SwiftUI

struct ConsoleSectionSwitcher: View {
    @EnvironmentObject var nav: ConsoleNavigationStore

    var body: some View {
        HStack(spacing: 8) {
            ForEach(ConsoleSection.allCases) { section in
                Button { nav.selectedSection = section } label: {
                    HStack(spacing: 6) {
                        Image(systemName: section.icon)
                            .font(.system(size: 11, weight: .bold))
                        Text(section.rawValue)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.white.opacity(nav.selectedSection == section ? 0.96 : 0.74))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(nav.selectedSection == section ? Color(red: 0.27, green: 0.42, blue: 0.95) : Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct ConsoleSectionBody: View {
    @EnvironmentObject var nav: ConsoleNavigationStore

    var body: some View {
        switch nav.selectedSection {
        case .command:
            EmptyView() // handled directly in RightPanelView
        case .tasks:
            TaskBoardView()
        case .review:
            ReviewQueueView()
        case .approvals:
            ApprovalsView()
        case .deliverables:
            DeliverablesView()
        }
    }
}

private struct ConsoleInfoPanel: View {
    let title: String
    let subtitle: String
    let bullets: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.system(size: 20, weight: .bold, design: .serif))
                .foregroundColor(.white.opacity(0.95))
            Text(subtitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color.white.opacity(0.68))
            VStack(alignment: .leading, spacing: 10) {
                ForEach(bullets, id: \.self) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Circle().fill(Color(red: 0.32, green: 0.52, blue: 1.0)).frame(width: 7, height: 7).padding(.top, 5)
                        Text(item)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundColor(.white.opacity(0.84))
                    }
                }
            }
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.06), lineWidth: 1))
        )
        .padding(12)
    }
}
