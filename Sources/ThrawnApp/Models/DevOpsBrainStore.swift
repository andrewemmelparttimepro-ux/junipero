import Foundation

enum DevOpsBrainKind: String, Codable {
    case openclawCodexXHigh
    case codex55XHigh
    case ollama
}

struct DevOpsBrainSelection: Codable, Equatable {
    var kind: DevOpsBrainKind
    var model: String

    static let openClawCodexXHigh = DevOpsBrainSelection(
        kind: .openclawCodexXHigh,
        model: ProviderRouter.premiumOpenClawModel
    )

    static let codex55XHigh = DevOpsBrainSelection(
        kind: .codex55XHigh,
        model: ProviderRouter.glmModel
    )

    var displayName: String {
        switch kind {
        case .openclawCodexXHigh:
            return "Thrawn · GPT-5.4"
        case .codex55XHigh:
            return "Thrawn · GPT-5.4"
        case .ollama:
            return "Thrawn · GPT-5.4"
        }
    }

    var providerLabel: String {
        switch kind {
        case .openclawCodexXHigh, .codex55XHigh, .ollama: return "OPENCLAW"
        }
    }
}

@MainActor
final class DevOpsBrainStore: ObservableObject {
    @Published var selection: DevOpsBrainSelection {
        didSet { save() }
    }

    private static let savePath = ThrawnPaths.appSupportDir
        .appendingPathComponent("devops-brain.json")

    init() {
        if let data = try? Data(contentsOf: Self.savePath),
           let decoded = try? JSONDecoder().decode(DevOpsBrainSelection.self, from: data) {
            self.selection = decoded.kind == .openclawCodexXHigh ? decoded : .openClawCodexXHigh
        } else {
            self.selection = .openClawCodexXHigh
        }
    }

    func selectOpenClawCodexXHigh() {
        selection = .openClawCodexXHigh
    }

    func selectCodex55XHigh() {
        selection = .openClawCodexXHigh
    }

    func selectOllama(model: String) {
        selection = .openClawCodexXHigh
    }

    func route(openAIConfigured: Bool) -> RoutedProvider {
        switch selection.kind {
        case .openclawCodexXHigh, .codex55XHigh, .ollama:
            return RoutedProvider(
                backend: .openclaw,
                model: ProviderRouter.premiumOpenClawModel,
                isFallback: false,
                reasoningEffort: ProviderRouter.premiumOpenClawThinkingLevel,
                allowFallback: false
            )
        }
    }

    var fallbackOllamaModel: String {
        if selection.kind == .ollama { return selection.model }
        return ProviderRouter.localModel
    }

    private func save() {
        let data: Data
        do {
            data = try JSONEncoder().encode(selection)
        } catch {
            FlightRecorder.logError(
                source: "devopsbrain:save",
                message: "Encode failed: \(error.localizedDescription)"
            )
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: Self.savePath.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: Self.savePath, options: .atomic)
        } catch {
            FlightRecorder.logError(
                source: "devopsbrain:save",
                message: "Write failed: \(error.localizedDescription)"
            )
        }
    }
}
