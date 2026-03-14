import SwiftUI

struct ConsoleSectionSwitcher: View {
    @EnvironmentObject var nav: ConsoleNavigationStore

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ConsoleSection.allCases) { section in
                Button { nav.selectedSection = section } label: {
                    HStack(spacing: 5) {
                        Image(systemName: section.icon)
                            .font(.system(size: 10, weight: .bold))
                        Text(section.rawValue)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(nav.selectedSection == section ? .white : Color.white.opacity(0.55))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(nav.selectedSection == section ? Color.chissDeep : Color.white.opacity(0.05))
                            .overlay(
                                Capsule().stroke(
                                    nav.selectedSection == section ? Color.chissPrimary.opacity(0.55) : Color.clear,
                                    lineWidth: 1
                                )
                            )
                    )
                    .shadow(color: nav.selectedSection == section ? Color.chissPrimary.opacity(0.20) : .clear, radius: 6)
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
            PrimarySessionView()
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
