import AppKit
import SwiftUI

struct CitadelView: View {
    @EnvironmentObject var nav: ConsoleNavigationStore

    @State private var boards: [CitadelProductBoard] = []
    @State private var pages: [CitadelPage] = []
    @State private var selectedId = "overview"
    @State private var lastLoaded: Date?

    private var selectedBoard: CitadelProductBoard? {
        boards.first { $0.id == selectedId }
    }

    private var totalRuns: Int { boards.reduce(0) { $0 + $1.runs.count } }
    private var warningRuns: Int { boards.flatMap(\.runs).filter { $0.status == .warning }.count }
    private var failedRuns: Int { boards.flatMap(\.runs).filter { $0.status == .failed || $0.status == .error }.count }
    private var screenshotCount: Int { boards.flatMap(\.runs).reduce(0) { $0 + $1.screenshots.count } }

    var body: some View {
        ZStack {
            Color.obsidian.ignoresSafeArea()
            LinearGradient(
                colors: [
                    Color(red: 0.045, green: 0.055, blue: 0.055).opacity(0.96),
                    Color.obsidian.opacity(0.99),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                header
                content
            }
            .padding(18)
        }
        .onAppear(perform: loadCitadel)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    nav.dismissCitadel()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                    Text("Back")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(Color.chissPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(Color.chissDeep.opacity(0.55))
                        .overlay(Capsule().stroke(Color.chissPrimary.opacity(0.28), lineWidth: 1))
                )
            }
            .buttonStyle(.plain)

            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.ndaiGreen.opacity(0.12))
                    .frame(width: 42, height: 42)
                Image(systemName: "building.columns.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.ndaiGreen)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("THE CITADEL")
                    .font(.system(size: 21, weight: .black, design: .serif))
                    .tracking(2.2)
                    .foregroundColor(.white.opacity(0.92))
                    .shadow(color: Color.chissPrimary.opacity(0.30), radius: 8)
                Text("Human-facing command memory. The raw proof vault stays immutable underneath.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.48))
            }

            Spacer()

            if let lastLoaded {
                Text("Loaded \(lastLoaded.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(Color.chissPrimary.opacity(0.56))
            }

            CitadelActionButton(label: "Vault", icon: "archivebox") {
                NSWorkspace.shared.activateFileViewerSelecting([ProductRegistryBootstrap.proofsRoot])
            }

            CitadelActionButton(label: "Reload", icon: "arrow.clockwise") {
                loadCitadel()
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.obsidianMid.opacity(0.86))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var content: some View {
        HStack(alignment: .top, spacing: 14) {
            indexRail
                .frame(width: 275)

            ScrollView {
                if selectedId == "overview" {
                    overview
                } else if let board = selectedBoard {
                    productBoard(board)
                } else {
                    emptyState
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.obsidianMid.opacity(0.58))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var indexRail: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("BOARD")
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .tracking(2.4)
                .foregroundColor(Color.ndaiGreen.opacity(0.78))

            CitadelIndexButton(
                title: "Command Overview",
                subtitle: "\(boards.count) projects · \(totalRuns) proof runs",
                icon: "square.grid.2x2.fill",
                selected: selectedId == "overview",
                badge: failedRuns > 0 ? "\(failedRuns)" : nil
            ) {
                selectedId = "overview"
            }

            Text("PROJECTS")
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .tracking(2.4)
                .foregroundColor(Color.chissPrimary.opacity(0.55))
                .padding(.top, 6)

            ForEach(boards) { board in
                CitadelIndexButton(
                    title: board.name,
                    subtitle: board.latest?.status.displayName ?? "No proof yet",
                    icon: board.latest?.status.icon ?? "shippingbox.fill",
                    selected: selectedId == board.id,
                    badge: board.issueCount > 0 ? "\(board.issueCount)" : nil,
                    accent: board.latest?.status.color ?? Color.chissPrimary
                ) {
                    selectedId = board.id
                }
            }

            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.20))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.07), lineWidth: 1)
                )
        )
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("OPERATING PICTURE")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .tracking(2.6)
                        .foregroundColor(Color.ndaiGreen.opacity(0.75))
                    Text("What your team is presenting right now")
                        .font(.system(size: 22, weight: .black, design: .serif))
                        .foregroundColor(.white.opacity(0.92))
                }
                Spacer()
                if let rolling = pages.first(where: { $0.id == "rolling-72h" }) {
                    CitadelActionButton(label: "Rolling Brief", icon: "doc.text") {
                        NSWorkspace.shared.open(rolling.path)
                    }
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                MetricTile(label: "Projects", value: "\(boards.count)", icon: "shippingbox.fill", color: Color.chissPrimary)
                MetricTile(label: "Proof Runs", value: "\(totalRuns)", icon: "checklist", color: Color.ndaiGreen)
                MetricTile(label: "Warnings", value: "\(warningRuns)", icon: "exclamationmark.triangle.fill", color: Color.orange)
                MetricTile(label: "Screenshots", value: "\(screenshotCount)", icon: "photo.on.rectangle", color: Color(red: 0.58, green: 0.76, blue: 0.95))
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 270), spacing: 12)], spacing: 12) {
                ForEach(boards) { board in
                    ProductSummaryCard(board: board) {
                        selectedId = board.id
                    }
                }
            }

            if !boards.flatMap(\.runs).isEmpty {
                SectionHeader(title: "LATEST PROOFS", subtitle: "Readable cards backed by immutable vault folders")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 245), spacing: 12)], spacing: 12) {
                    ForEach(Array(boards.flatMap(\.runs).sorted(by: { $0.startedAt > $1.startedAt }).prefix(6))) { run in
                        ProofRunCard(run: run, productName: productTitle(for: run.productId))
                    }
                }
            }
        }
        .padding(16)
    }

    private func productBoard(_ board: CitadelProductBoard) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                latestProofStage(board)

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(board.name)
                                .font(.system(size: 26, weight: .black, design: .serif))
                                .foregroundColor(.white.opacity(0.94))
                            Text(board.registry?.rootPath ?? "Root not recorded")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(Color.chissPrimary.opacity(0.55))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        StatusPill(status: board.latest?.status ?? .unknown)
                    }

                    Text(board.executiveSummary)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(.white.opacity(0.72))
                        .lineSpacing(4)

                    HStack(spacing: 8) {
                        MiniFact(label: "Proofs", value: "\(board.runs.count)")
                        MiniFact(label: "Images", value: "\(board.screenshotCount)")
                        MiniFact(label: "Logs", value: "\(board.logCount)")
                        MiniFact(label: "Clarity", value: board.claritySummary)
                    }

                    HStack(spacing: 8) {
                        if let page = board.page {
                            CitadelActionButton(label: "Citadel Note", icon: "doc.text") {
                                NSWorkspace.shared.open(page.path)
                            }
                        }
                        CitadelActionButton(label: "Raw Vault", icon: "archivebox") {
                            NSWorkspace.shared.activateFileViewerSelecting([board.vaultURL])
                        }
                        if let dashboard = board.registry?.clarity?.dashboardUrl, !dashboard.isEmpty,
                           let url = URL(string: dashboard) {
                            CitadelActionButton(label: "Clarity", icon: "chart.xyaxis.line") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
            }

            if let latest = board.latest, let clarity = latest.clarity, clarity.needsAttention {
                ClarityCallout(clarity: clarity)
            }

            SectionHeader(title: "PROOF WALL", subtitle: "Thumbnails and verdicts from immutable proof runs")
            if board.runs.isEmpty {
                EmptyProofCard()
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 12)], spacing: 12) {
                    ForEach(board.runs) { run in
                        ProofRunCard(run: run, productName: board.name)
                    }
                }
            }

            if let page = board.page, !page.content.isEmpty {
                SectionHeader(title: "SAMWELL'S NOTES", subtitle: "Human-readable synthesis; source opens in the Citadel note")
                NotesPreview(text: page.content, source: page.path)
            }
        }
        .padding(16)
    }

    private func latestProofStage(_ board: CitadelProductBoard) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let shot = board.latest?.screenshots.first {
                LocalProofImage(url: shot, cornerRadius: 8)
                    .frame(width: 310, height: 188)
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .frame(width: 310, height: 188)
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "photo")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundColor(Color.chissPrimary.opacity(0.42))
                            Text("No visual proof yet")
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundColor(.white.opacity(0.46))
                        }
                    )
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("LATEST PROOF")
                    .font(.system(size: 8.5, weight: .black, design: .monospaced))
                    .tracking(1.8)
                    .foregroundColor(.white.opacity(0.62))
                Text(board.latest?.startedAt.formatted(date: .abbreviated, time: .shortened) ?? "Awaiting first run")
                    .font(.system(size: 10.5, weight: .heavy))
                    .foregroundColor(.white.opacity(0.86))
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.48))
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke((board.latest?.status.color ?? Color.chissPrimary).opacity(0.36), lineWidth: 1)
        )
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "building.columns")
                .font(.system(size: 34, weight: .semibold))
                .foregroundColor(Color.chissPrimary.opacity(0.48))
            Text("The Citadel is empty")
                .font(.system(size: 15, weight: .heavy))
                .foregroundColor(.white.opacity(0.72))
            Text("No rolling brief or product pages were found.")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.42))
        }
        .frame(maxWidth: .infinity, minHeight: 420)
    }

    private func loadCitadel() {
        ProductRegistryBootstrap.bootstrap()

        let loadedPages = loadPages()
        pages = loadedPages

        let runs = loadProofRuns()
        boards = ProductRegistryBootstrap.defaultProducts.map { product in
            let page = loadedPages.first { $0.id == product.id }
            let productRuns = runs
                .filter { $0.productId == product.id }
                .sorted { $0.startedAt > $1.startedAt }
            return CitadelProductBoard(
                id: product.id,
                name: product.name,
                registry: product,
                page: page,
                runs: productRuns,
                vaultURL: ProductRegistryBootstrap.proofsRoot.appendingPathComponent(product.id, isDirectory: true)
            )
        }

        if selectedId != "overview", !boards.contains(where: { $0.id == selectedId }) {
            selectedId = "overview"
        }
        lastLoaded = Date()
    }

    private func loadPages() -> [CitadelPage] {
        var loaded: [CitadelPage] = []
        let rolling = ProductRegistryBootstrap.wikiRoot.appendingPathComponent("rolling-72h.md")
        loaded.append(CitadelPage(
            id: "rolling-72h",
            title: "Rolling 72-Hour Brief",
            path: rolling,
            content: readText(rolling)
        ))

        let productRoot = ProductRegistryBootstrap.wikiRoot.appendingPathComponent("products", isDirectory: true)
        let productPages = (try? FileManager.default.contentsOfDirectory(
            at: productRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        for pageURL in productPages where pageURL.pathExtension == "md" {
            let id = pageURL.deletingPathExtension().lastPathComponent
            loaded.append(CitadelPage(
                id: id,
                title: productTitle(for: id),
                path: pageURL,
                content: readText(pageURL)
            ))
        }

        return loaded
    }

    private func loadProofRuns() -> [CitadelProofRun] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: ProductRegistryBootstrap.proofsRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var runs: [CitadelProofRun] = []
        for case let url as URL in enumerator {
            if url.lastPathComponent == "proof-run.json",
               let run = CitadelProofRun.decodeProofRun(url) {
                runs.append(run)
            } else if url.lastPathComponent == "proof.json",
                      let run = CitadelProofRun.decodeLegacyProof(url) {
                runs.append(run)
            }
        }
        return runs
    }

    private func readText(_ url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    private func productTitle(for id: String) -> String {
        ProductRegistryBootstrap.defaultProducts.first(where: { $0.id == id })?.name
            ?? id.replacingOccurrences(of: "-", with: " ").capitalized
    }
}

private struct CitadelProductBoard: Identifiable {
    let id: String
    let name: String
    let registry: ProductSpec?
    let page: CitadelPage?
    let runs: [CitadelProofRun]
    let vaultURL: URL

    var latest: CitadelProofRun? { runs.first }
    var issueCount: Int { runs.filter { $0.status == .warning || $0.status == .failed || $0.status == .error }.count }
    var screenshotCount: Int { runs.reduce(0) { $0 + $1.screenshots.count } }
    var logCount: Int { runs.reduce(0) { $0 + $1.logs.count } }

    var claritySummary: String {
        guard let clarity = latest?.clarity else {
            return registry?.clarity?.expected == true ? "Expected" : "N/A"
        }
        if clarity.installed { return "Installed" }
        if !clarity.dashboardUrl.isEmpty { return "Dashboard" }
        return "Missing"
    }

    var executiveSummary: String {
        if let latest {
            switch latest.status {
            case .passed:
                return "Latest run passed. Proofs are available for inspection, with screenshots and logs preserved in the vault."
            case .warning:
                return latest.clarity?.recommendation ?? "Latest run completed with warnings. Review the proof wall and raw verdict before taking action."
            case .failed, .error:
                return latest.error ?? "Latest run failed. This project needs attention before it can be considered healthy."
            case .pending:
                return "A proof run is pending. Wait for Thrawn to synthesize the evidence."
            case .unknown:
                return "Proof history exists, but the latest status was not recognized. Inspect the raw vault."
            }
        }
        return "No proof runs have been captured yet. This project is registered, but it has not presented evidence to The Citadel."
    }
}

private struct CitadelPage: Identifiable {
    let id: String
    let title: String
    let path: URL
    let content: String
}

private struct CitadelProofRun: Identifiable {
    let id: String
    let productId: String
    let startedAt: Date
    let completedAt: Date?
    let status: ProofStatus
    let screenshots: [URL]
    let logs: [URL]
    let summaryPath: URL?
    let vaultURL: URL
    let clarity: CitadelClarity?
    let error: String?

    static func decodeProofRun(_ url: URL) -> CitadelProofRun? {
        guard let data = try? Data(contentsOf: url),
              let raw = try? JSONDecoder.citadel.decode(RawProofRun.self, from: data)
        else { return nil }
        return CitadelProofRun(
            id: raw.id,
            productId: raw.productId,
            startedAt: raw.startedAt,
            completedAt: raw.completedAt,
            status: ProofStatus(rawValue: raw.status.lowercased()) ?? .unknown,
            screenshots: raw.screenshots.map(URL.init(fileURLWithPath:)),
            logs: raw.logs.map(URL.init(fileURLWithPath:)),
            summaryPath: raw.summaryPath.map(URL.init(fileURLWithPath:)),
            vaultURL: url.deletingLastPathComponent(),
            clarity: raw.clarity,
            error: nil
        )
    }

    static func decodeLegacyProof(_ url: URL) -> CitadelProofRun? {
        guard let data = try? Data(contentsOf: url),
              let raw = try? JSONDecoder.citadel.decode(LegacyProof.self, from: data)
        else { return nil }
        return CitadelProofRun(
            id: raw.runId,
            productId: productId(for: raw.product),
            startedAt: raw.timestamp,
            completedAt: raw.timestamp,
            status: raw.error == nil ? .unknown : .error,
            screenshots: [],
            logs: [],
            summaryPath: nil,
            vaultURL: url.deletingLastPathComponent(),
            clarity: nil,
            error: raw.error
        )
    }

    private static func productId(for productName: String) -> String {
        ProductRegistryBootstrap.defaultProducts.first {
            $0.name.localizedCaseInsensitiveCompare(productName) == .orderedSame
        }?.id ?? productName.lowercased().replacingOccurrences(of: " ", with: "-")
    }
}

private enum ProofStatus: String {
    case pending
    case passed
    case warning
    case failed
    case error
    case unknown

    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .passed: return "Passed"
        case .warning: return "Warning"
        case .failed: return "Failed"
        case .error: return "Needs Setup"
        case .unknown: return "Unknown"
        }
    }

    var color: Color {
        switch self {
        case .passed: return Color.ndaiGreen
        case .warning: return Color.orange
        case .failed, .error: return Color.sithGlow
        case .pending: return Color.chissPrimary
        case .unknown: return Color.white.opacity(0.55)
        }
    }

    var icon: String {
        switch self {
        case .passed: return "checkmark.seal.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .failed, .error: return "xmark.octagon.fill"
        case .pending: return "clock.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }
}

private struct CitadelClarity: Codable, Equatable {
    var dashboardUrl: String
    var evidence: [String]
    var expected: Bool
    var installed: Bool
    var notes: String
    var projectId: String
    var recommendation: String
    var scannedFiles: Int
    var status: String

    var needsAttention: Bool {
        expected && (!installed || projectId.isEmpty || status.localizedCaseInsensitiveContains("missing"))
    }
}

private struct RawProofRun: Decodable {
    let id: String
    let productId: String
    let startedAt: Date
    let completedAt: Date?
    let status: String
    let screenshots: [String]
    let logs: [String]
    let summaryPath: String?
    let clarity: CitadelClarity?
}

private struct LegacyProof: Decodable {
    let product: String
    let timestamp: Date
    let runId: String
    let error: String?

    enum CodingKeys: String, CodingKey {
        case product
        case timestamp
        case runId = "run_id"
        case error
    }
}

private struct CitadelIndexButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let selected: Bool
    let badge: String?
    var accent: Color = Color.ndaiGreen
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(selected ? accent : Color.chissPrimary.opacity(0.65))
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundColor(.white.opacity(selected ? 0.92 : 0.66))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(.white.opacity(0.38))
                        .lineLimit(1)
                }
                Spacer()
                if let badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundColor(.black.opacity(0.86))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(accent))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Color.white.opacity(0.08) : Color.white.opacity(0.035))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(selected ? accent.opacity(0.32) : Color.white.opacity(0.05), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ProductSummaryCard: View {
    let board: CitadelProductBoard
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(board.name)
                            .font(.system(size: 16, weight: .black, design: .serif))
                            .foregroundColor(.white.opacity(0.90))
                        Text(board.latest?.startedAt.formatted(date: .abbreviated, time: .shortened) ?? "No proof yet")
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .foregroundColor(Color.chissPrimary.opacity(0.52))
                    }
                    Spacer()
                    StatusPill(status: board.latest?.status ?? .unknown)
                }

                if let shot = board.latest?.screenshots.first {
                    LocalProofImage(url: shot, cornerRadius: 6)
                        .frame(height: 116)
                } else {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                        .frame(height: 116)
                        .overlay(
                            Text("Awaiting visual proof")
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundColor(.white.opacity(0.40))
                        )
                }

                Text(board.executiveSummary)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.62))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                HStack {
                    MiniFact(label: "Proofs", value: "\(board.runs.count)")
                    MiniFact(label: "Clarity", value: board.claritySummary)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color.ndaiGreen.opacity(0.86))
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.045))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke((board.latest?.status.color ?? Color.chissPrimary).opacity(0.18), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ProofRunCard: View {
    let run: CitadelProofRun
    let productName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let shot = run.screenshots.first {
                LocalProofImage(url: shot, cornerRadius: 6)
                    .frame(height: 128)
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .frame(height: 128)
                    .overlay(
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(Color.chissPrimary.opacity(0.42))
                    )
            }

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(productName)
                        .font(.system(size: 12, weight: .black))
                        .foregroundColor(.white.opacity(0.88))
                    Text(run.startedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(Color.chissPrimary.opacity(0.50))
                }
                Spacer()
                StatusPill(status: run.status)
            }

            if let clarity = run.clarity, clarity.needsAttention {
                Text(clarity.recommendation)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(Color.orange.opacity(0.82))
                    .lineLimit(3)
            } else if let error = run.error {
                Text(error)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(Color.sithGlow.opacity(0.82))
                    .lineLimit(3)
            }

            HStack(spacing: 7) {
                if let summary = run.summaryPath {
                    SmallIconButton(icon: "doc.text", label: "Verdict") {
                        NSWorkspace.shared.open(summary)
                    }
                }
                SmallIconButton(icon: "folder", label: "Vault") {
                    NSWorkspace.shared.activateFileViewerSelecting([run.vaultURL])
                }
                if let shot = run.screenshots.first {
                    SmallIconButton(icon: "photo", label: "Image") {
                        NSWorkspace.shared.open(shot)
                    }
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(run.status.color.opacity(0.20), lineWidth: 1)
                )
        )
    }
}

private struct LocalProofImage: View {
    let url: URL
    let cornerRadius: CGFloat
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.05))
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onAppear {
            if image == nil {
                image = NSImage(contentsOf: url)
            }
        }
    }
}

private struct StatusPill: View {
    let status: ProofStatus

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: status.icon)
                .font(.system(size: 8.5, weight: .bold))
            Text(status.displayName.uppercased())
                .font(.system(size: 8.5, weight: .black, design: .monospaced))
                .tracking(0.8)
        }
        .foregroundColor(status.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Capsule().fill(status.color.opacity(0.10)))
        .overlay(Capsule().stroke(status.color.opacity(0.24), lineWidth: 1))
    }
}

private struct MetricTile: View {
    let label: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(color)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 6).fill(color.opacity(0.11)))
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(.white.opacity(0.90))
                Text(label.uppercased())
                    .font(.system(size: 8.5, weight: .black, design: .monospaced))
                    .tracking(1.4)
                    .foregroundColor(.white.opacity(0.38))
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.045))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.07), lineWidth: 1))
        )
    }
}

private struct MiniFact: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 7.5, weight: .black, design: .monospaced))
                .tracking(1.1)
                .foregroundColor(.white.opacity(0.34))
            Text(value)
                .font(.system(size: 11, weight: .heavy))
                .foregroundColor(.white.opacity(0.80))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.045))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.07), lineWidth: 1))
        )
    }
}

private struct ClarityCallout: View {
    let clarity: CitadelClarity

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(Color.orange)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.orange.opacity(0.12)))

            VStack(alignment: .leading, spacing: 5) {
                Text("MICROSOFT CLARITY NEEDS ATTENTION")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .tracking(1.7)
                    .foregroundColor(Color.orange.opacity(0.86))
                Text(clarity.recommendation)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.75))
                Text("Rage clicks, dead clicks, recordings, heatmaps, funnels, and smart events should become primary change signals once connected.")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(.white.opacity(0.46))
            }
            Spacer()
            if let url = URL(string: clarity.dashboardUrl), !clarity.dashboardUrl.isEmpty {
                CitadelActionButton(label: "Dashboard", icon: "arrow.up.right.square") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.orange.opacity(0.07))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.orange.opacity(0.22), lineWidth: 1))
        )
    }
}

private struct NotesPreview: View {
    let text: String
    let source: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(trimmedNotes)
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.64))
                .lineSpacing(4)
                .textSelection(.enabled)
            CitadelActionButton(label: "Open Source Note", icon: "doc.text") {
                NSWorkspace.shared.open(source)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.18))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.07), lineWidth: 1))
        )
    }

    private var trimmedNotes: String {
        let lines = text
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return lines.prefix(14).joined(separator: "\n")
    }
}

private struct EmptyProofCard: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(Color.chissPrimary.opacity(0.45))
            VStack(alignment: .leading, spacing: 3) {
                Text("No proof runs yet")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundColor(.white.opacity(0.70))
                Text("When Thrawn produces evidence, it will appear here.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.42))
            }
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.035))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.06), lineWidth: 1))
        )
    }
}

private struct SectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .tracking(2.2)
                .foregroundColor(Color.ndaiGreen.opacity(0.78))
            Rectangle()
                .fill(Color.ndaiGreen.opacity(0.16))
                .frame(height: 1)
            Text(subtitle)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundColor(.white.opacity(0.34))
        }
    }
}

private struct SmallIconButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
                Text(label)
                    .font(.system(size: 9, weight: .heavy))
            }
            .foregroundColor(Color.chissPrimary.opacity(0.82))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.white.opacity(0.055)))
            .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct CitadelActionButton: View {
    let label: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                Text(label)
                    .font(.system(size: 10, weight: .heavy))
            }
            .foregroundColor(Color.chissPrimary.opacity(0.86))
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.06))
                    .overlay(Capsule().stroke(Color.chissPrimary.opacity(0.18), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }
}

private extension JSONDecoder {
    static var citadel: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = ISO8601DateFormatter.citadel.date(from: value) {
                return date
            }
            if let date = DateFormatter.citadelLegacy.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(value)")
        }
        return decoder
    }
}

private extension ISO8601DateFormatter {
    static let citadel: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

private extension DateFormatter {
    static let citadelLegacy: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        formatter.timeZone = .current
        return formatter
    }()
}
