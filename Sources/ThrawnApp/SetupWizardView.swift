import SwiftUI

// MARK: - Setup Wizard  ·  Thrawn Console
// Visual language: deep-space CIC terminal. Subtle geometry, scan-line energy,
// hexagonal motifs. Star Wars DNA is in the shapes and cadence, never the logos.

struct SetupWizardView: View {
    @EnvironmentObject var bootstrap: ThrawnBootstrap
    @EnvironmentObject var ollama: OllamaClient
    @EnvironmentObject var openaiClient: OpenAIClient
    @State private var scanOffset: CGFloat = -1.0
    @State private var glowPulse: Double = 0.6
    @State private var hexRotation: Double = 0
    @State private var systemsRevealed = false
    @State private var selectedProvider: AIProvider? = .gemini
    @State private var openAIToken: String = ""
    @State private var openAIModel: String = AIProvider.chatgpt.defaultModel
    @State private var geminiAPIKeyInput: String = ""
    @State private var geminiModel: String = AIProvider.gemini.defaultModel

    var body: some View {
        ZStack {
            // Deep space backdrop
            backgroundLayer

            VStack(spacing: 0) {
                // Header crest
                headerCrest
                    .padding(.top, 28)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 20) {
                        // API credentials (always shown — this is the core setup)
                        credentialsCard

                        // Systems status grid
                        systemsStatusCard

                        // Memory subsystem (optional)
                        memoryCard

                        // Capability & guardrails
                        capabilityCard

                        // Action bar
                        actionBar
                            .padding(.top, 4)
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 16)
                    .padding(.bottom, 28)
                }
            }

            // Scan-line sweep
            scanLineOverlay
        }
        .frame(width: 580, height: 680)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear {
            withAnimation(.linear(duration: 4.0).repeatForever(autoreverses: false)) {
                scanOffset = 2.0
            }
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                glowPulse = 1.0
            }
            withAnimation(.linear(duration: 30).repeatForever(autoreverses: false)) {
                hexRotation = 360
            }
            withAnimation(.easeOut(duration: 0.8).delay(0.2)) {
                systemsRevealed = true
            }
        }
    }

    // MARK: - Background

    private var backgroundLayer: some View {
        ZStack {
            // Base obsidian
            Color.obsidian

            // Radial vignette from center
            RadialGradient(
                colors: [
                    Color.chissDeep.opacity(0.35),
                    Color.obsidian.opacity(0.95)
                ],
                center: .center,
                startRadius: 40,
                endRadius: 380
            )

            // Subtle hex grid pattern
            hexGridOverlay
                .opacity(0.04)

            // Top-edge glow bar
            VStack {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.chissPrimary.opacity(0.0),
                                Color.chissPrimary.opacity(0.12 * glowPulse),
                                Color.chissPrimary.opacity(0.0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 1)
                Spacer()
            }

            // Corner accents — angular bracket marks (CIC terminal framing)
            cornerBrackets
        }
    }

    private var hexGridOverlay: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let hexSize: CGFloat = 24
                let w = hexSize * 1.732
                let h = hexSize * 2
                let cols = Int(size.width / w) + 2
                let rows = Int(size.height / (h * 0.75)) + 2

                for row in 0..<rows {
                    for col in 0..<cols {
                        let xOff: CGFloat = row % 2 == 0 ? 0 : w / 2
                        let x = CGFloat(col) * w + xOff
                        let y = CGFloat(row) * h * 0.75
                        let center = CGPoint(x: x, y: y)

                        var path = Path()
                        for i in 0..<6 {
                            let angle = CGFloat(i) * .pi / 3 - .pi / 6
                            let pt = CGPoint(
                                x: center.x + hexSize * cos(angle),
                                y: center.y + hexSize * sin(angle)
                            )
                            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                        }
                        path.closeSubpath()
                        context.stroke(path, with: .color(Color.chissPrimary), lineWidth: 0.5)
                    }
                }
            }
            .rotationEffect(.degrees(hexRotation))
            .scaleEffect(1.5)
        }
    }

    private var cornerBrackets: some View {
        ZStack {
            // Top-left
            VStack {
                HStack {
                    CornerBracket()
                        .stroke(Color.chissPrimary.opacity(0.25), lineWidth: 1)
                        .frame(width: 20, height: 20)
                        .padding(10)
                    Spacer()
                }
                Spacer()
            }
            // Top-right
            VStack {
                HStack {
                    Spacer()
                    CornerBracket()
                        .stroke(Color.chissPrimary.opacity(0.25), lineWidth: 1)
                        .frame(width: 20, height: 20)
                        .rotationEffect(.degrees(90))
                        .padding(10)
                }
                Spacer()
            }
            // Bottom-left
            VStack {
                Spacer()
                HStack {
                    CornerBracket()
                        .stroke(Color.chissPrimary.opacity(0.25), lineWidth: 1)
                        .frame(width: 20, height: 20)
                        .rotationEffect(.degrees(-90))
                        .padding(10)
                    Spacer()
                }
            }
            // Bottom-right
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    CornerBracket()
                        .stroke(Color.chissPrimary.opacity(0.25), lineWidth: 1)
                        .frame(width: 20, height: 20)
                        .rotationEffect(.degrees(180))
                        .padding(10)
                }
            }
        }
    }

    // MARK: - Scan Line

    private var scanLineOverlay: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.chissPrimary.opacity(0.0),
                            Color.chissPrimary.opacity(0.06),
                            Color.chissPrimary.opacity(0.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 60)
                .offset(y: geo.size.height * scanOffset)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Header Crest

    private var headerCrest: some View {
        VStack(spacing: 10) {
            // Geometric crest — concentric rings with angular cuts
            ZStack {
                // Outer ring
                Circle()
                    .stroke(Color.chissPrimary.opacity(0.18), lineWidth: 1)
                    .frame(width: 64, height: 64)
                // Inner ring
                Circle()
                    .stroke(Color.chissPrimary.opacity(0.30), lineWidth: 1)
                    .frame(width: 44, height: 44)
                // Core glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.chissPrimary.opacity(0.50 * glowPulse),
                                Color.chissPrimary.opacity(0.08)
                            ],
                            center: .center,
                            startRadius: 2,
                            endRadius: 20
                        )
                    )
                    .frame(width: 40, height: 40)
                // Center letter
                Text("T")
                    .font(.system(size: 22, weight: .bold, design: .serif))
                    .foregroundColor(Color.chissPrimary)
                    .shadow(color: Color.chissPrimary.opacity(0.60), radius: 8)
            }

            Text("SYSTEM CONFIGURATION")
                .font(.system(size: 10, weight: .heavy))
                .tracking(4)
                .foregroundColor(Color.chissPrimary.opacity(0.55))

            // Thin ruled line
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.chissPrimary.opacity(0.0),
                            Color.chissPrimary.opacity(0.20),
                            Color.chissPrimary.opacity(0.0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
                .padding(.horizontal, 40)
        }
    }

    // MARK: - Cards

    private var credentialsCard: some View {
        terminalCard(label: "CONNECT AI PROVIDER", icon: "link.circle.fill") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Choose your AI provider to connect THRAWN. Gemini is recommended — sign in with your Google account for free.")
                    .font(.system(size: 11))
                    .foregroundColor(Color.white.opacity(0.55))
                    .lineSpacing(2)

                // Provider cards
                VStack(spacing: 8) {
                    // Gemini — Primary, OAuth
                    providerCardButton(
                        provider: .gemini,
                        badge: "RECOMMENDED",
                        isExpanded: selectedProvider == .gemini
                    ) {
                        withAnimation(.spring(response: 0.3)) { selectedProvider = .gemini }
                    }

                    // Claude — API Key
                    providerCardButton(
                        provider: .claude,
                        badge: nil,
                        isExpanded: selectedProvider == .claude
                    ) {
                        withAnimation(.spring(response: 0.3)) { selectedProvider = .claude }
                    }

                    // ChatGPT — API Key
                    providerCardButton(
                        provider: .chatgpt,
                        badge: nil,
                        isExpanded: selectedProvider == .chatgpt
                    ) {
                        withAnimation(.spring(response: 0.3)) { selectedProvider = .chatgpt }
                    }
                }
            }
        }
    }

    // MARK: - Provider Card Button

    private func providerCardButton(provider: AIProvider, badge: String?, isExpanded: Bool, action: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            // Header row — always visible
            Button(action: action) {
                HStack(spacing: 10) {
                    // Provider icon with brand color
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: provider.brandGradient.map { $0.opacity(isExpanded ? 0.25 : 0.12) },
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 28, height: 28)
                        Image(systemName: provider.icon)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(provider.brandColor)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(provider.displayName)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white.opacity(isExpanded ? 0.95 : 0.70))

                            if let badge {
                                Text(badge)
                                    .font(.system(size: 7, weight: .black))
                                    .tracking(1)
                                    .foregroundColor(provider.brandColor)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule()
                                            .fill(provider.brandColor.opacity(0.12))
                                            .overlay(Capsule().stroke(provider.brandColor.opacity(0.25), lineWidth: 0.5))
                                    )
                            }

                            // Connected checkmark
                            if isProviderConnected(provider) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(Color(red: 0.3, green: 0.85, blue: 0.55))
                            }
                        }

                        Text(provider.subtitle)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundColor(.white.opacity(0.40))
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.25))
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isExpanded ? provider.brandColor.opacity(0.06) : Color.white.opacity(0.02))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(
                                    isExpanded ? provider.brandColor.opacity(0.25) : Color.white.opacity(0.06),
                                    lineWidth: 1
                                )
                        )
                )
            }
            .buttonStyle(.plain)

            // Expanded auth form
            if isExpanded {
                providerAuthForm(for: provider)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Provider Auth Forms

    @ViewBuilder
    private func providerAuthForm(for provider: AIProvider) -> some View {
        switch provider {
        case .gemini:
            geminiOAuthForm
        case .claude:
            apiKeyForm(
                provider: .claude,
                placeholder: "sk-ant-api03-...",
                getKeyLabel: "Get API Key from Anthropic",
                token: $bootstrap.providerToken,
                model: $bootstrap.providerModel
            )
        case .chatgpt:
            apiKeyForm(
                provider: .chatgpt,
                placeholder: "sk-proj-...",
                getKeyLabel: "Get API Key from OpenAI",
                token: $openAIToken,
                model: $openAIModel
            )
        }
    }

    private var geminiOAuthForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Ollama mode — no cloud OAuth needed
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.chissPrimary.opacity(0.15))
                        .frame(width: 28, height: 28)
                    Image(systemName: "cpu")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color.chissPrimary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ollama Mode Active")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.80))
                    Text(ollama.connected ? "Connected · \(ollama.selectedModel)" : "Not running — start Ollama")
                        .font(.system(size: 9.5))
                        .foregroundColor(.white.opacity(0.45))
                }
                Spacer()
            }
            if false {
                // Dead code block to keep the remaining references compiling

                // Or use API key
                HStack(spacing: 4) {
                    Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                    Text("or use API key")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.30))
                    Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                }
                .padding(.vertical, 2)

                TextField("Gemini API key...", text: $geminiAPIKeyInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.black.opacity(0.35))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.08), lineWidth: 1))
                    )
                    .foregroundColor(Color.chissPrimary)
            }

            if let error = ollama.lastError {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 8))
                        .foregroundColor(Color(red: 1.0, green: 0.55, blue: 0.55))
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundColor(Color(red: 1.0, green: 0.75, blue: 0.75))
                        .lineLimit(2)
                }
            }
        }
        .padding(.top, 8)
    }

    private func apiKeyForm(
        provider: AIProvider,
        placeholder: String,
        getKeyLabel: String,
        token: Binding<String>,
        model: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Deep link to get key
            Button(action: {
                if let url = provider.getKeyURL {
                    #if os(macOS)
                    NSWorkspace.shared.open(url)
                    #endif
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 10))
                    Text(getKeyLabel)
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(provider.brandColor)
            }
            .buttonStyle(.plain)

            // API key field
            VStack(alignment: .leading, spacing: 5) {
                fieldLabel("API KEY")
                SecureField(placeholder, text: token)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.black.opacity(0.40))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(
                                        keyValidationColor(for: token.wrappedValue, provider: provider),
                                        lineWidth: 1
                                    )
                            )
                    )
                    .foregroundColor(Color.chissPrimary)

                // Inline validation hint
                if !token.wrappedValue.isEmpty {
                    HStack(spacing: 4) {
                        if isKeyFormatValid(token.wrappedValue, provider: provider) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 8))
                                .foregroundColor(Color(red: 0.3, green: 0.85, blue: 0.55))
                            Text("Key format valid · \(provider.defaultModel)")
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundColor(Color(red: 0.3, green: 0.85, blue: 0.55).opacity(0.8))
                        } else {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 8))
                                .foregroundColor(Color(red: 1.0, green: 0.55, blue: 0.55))
                            Text("Unexpected key format")
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundColor(Color(red: 1.0, green: 0.55, blue: 0.55).opacity(0.8))
                        }
                    }
                }
            }

            // Model picker
            VStack(alignment: .leading, spacing: 5) {
                fieldLabel("MODEL")
                Picker("", selection: model) {
                    ForEach(provider.availableModels, id: \.self) { m in
                        Text(m).tag(m)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .padding(.leading, -8)
            }

            HStack(spacing: 5) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 8))
                    .foregroundColor(Color.chissPrimary.opacity(0.35))
                Text("Stored in macOS Keychain · Never leaves your device")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.35))
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Validation Helpers

    private func isProviderConnected(_ provider: AIProvider) -> Bool {
        // Ollama mode — always connected if Ollama is running
        return ollama.connected
    }

    private func isKeyFormatValid(_ key: String, provider: AIProvider) -> Bool {
        guard let prefix = provider.keyPrefix else { return !key.isEmpty }
        return key.hasPrefix(prefix) && key.count > prefix.count + 10
    }

    private func keyValidationColor(for key: String, provider: AIProvider) -> Color {
        if key.isEmpty { return Color.chissPrimary.opacity(0.15) }
        return isKeyFormatValid(key, provider: provider)
            ? Color(red: 0.3, green: 0.85, blue: 0.55).opacity(0.35)
            : Color(red: 1.0, green: 0.55, blue: 0.55).opacity(0.25)
    }

    /// Save provider config. Persists API keys to the keychain for cloud providers.
    private func saveProviderKeys() {
        switch selectedProvider {
        case .chatgpt:
            let trimmed = openAIToken.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            openaiClient.setAPIKey(trimmed)
            openaiClient.setModel(openAIModel)
        default:
            break  // Gemini uses OAuth; Ollama needs no key.
        }
    }

    private var systemsStatusCard: some View {
        terminalCard(label: "SUBSYSTEM STATUS", icon: "cpu") {
            VStack(spacing: 0) {
                ForEach(Array(ThrawnBootstrap.SetupStep.allCases.enumerated()), id: \.element.id) { index, step in
                    let state = bootstrap.stateForStep(step)
                    HStack(spacing: 10) {
                        // Status indicator — angular diamond
                        ZStack {
                            Diamond()
                                .fill(stepColor(state).opacity(0.15))
                                .frame(width: 14, height: 14)
                            Diamond()
                                .stroke(stepColor(state).opacity(0.50), lineWidth: 1)
                                .frame(width: 14, height: 14)
                            if state == .running {
                                Diamond()
                                    .fill(stepColor(state).opacity(glowPulse * 0.40))
                                    .frame(width: 14, height: 14)
                            }
                            Circle()
                                .fill(stepColor(state))
                                .frame(width: 4, height: 4)
                        }

                        Text(step.rawValue)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(Color.white.opacity(state == .done ? 0.80 : 0.55))

                        Spacer()

                        Text(stepStatusLabel(state))
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1)
                            .foregroundColor(stepColor(state).opacity(0.80))
                    }
                    .padding(.vertical, 7)
                    .padding(.horizontal, 4)
                    .opacity(systemsRevealed ? 1.0 : 0.0)
                    .offset(x: systemsRevealed ? 0 : -20)
                    .animation(.easeOut(duration: 0.4).delay(Double(index) * 0.08), value: systemsRevealed)

                    if index < ThrawnBootstrap.SetupStep.allCases.count - 1 {
                        Rectangle()
                            .fill(Color.chissPrimary.opacity(0.06))
                            .frame(height: 1)
                    }
                }
            }

            if let error = bootstrap.errorText {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                        .foregroundColor(Color(red: 1.0, green: 0.55, blue: 0.55))
                    Text(error)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(Color(red: 1.0, green: 0.80, blue: 0.80))
                        .lineLimit(2)
                }
                .padding(.top, 8)
            }

            if !bootstrap.diagnosticsSummary.isEmpty {
                Text(bootstrap.diagnosticsSummary)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Color.white.opacity(0.40))
                    .lineLimit(3)
                    .padding(.top, 6)
            }
        }
    }

    private var memoryCard: some View {
        terminalCard(label: "MEMORY SUBSYSTEM · OPTIONAL", icon: "brain") {
            HStack(spacing: 12) {
                // Brain status orb
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    bootstrap.cogneeHealthy
                                        ? Color.chissPrimary.opacity(0.40 * glowPulse)
                                        : Color.white.opacity(0.05),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 2,
                                endRadius: 16
                            )
                        )
                        .frame(width: 32, height: 32)
                    Image(systemName: bootstrap.cogneeHealthy ? "brain.fill" : "brain")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(
                            bootstrap.cogneeHealthy
                                ? Color.chissPrimary
                                : Color.white.opacity(0.25)
                        )
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(bootstrap.cogneeHealthy ? "MEMORY CONNECTED" : "MEMORY NOT CONNECTED")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.5)
                        .foregroundColor(
                            bootstrap.cogneeHealthy
                                ? Color.chissPrimary.opacity(0.85)
                                : Color.white.opacity(0.40)
                        )
                    Text(bootstrap.cogneeHealthy ? bootstrap.cogneeStatusText : "Thrawn works without memory. Connect Cognee for enhanced recall.")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Color.white.opacity(0.45))
                        .lineLimit(2)
                }

                Spacer()
            }
        }
    }

    private var capabilityCard: some View {
        terminalCard(label: "GUARDRAIL PROTOCOL", icon: "shield.lefthalf.filled") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Capability Mode", selection: Binding(
                    get: { bootstrap.liabilityMode },
                    set: { bootstrap.setLiabilityMode($0) }
                )) {
                    Text("Standard").tag(LiabilityMode.idiot)
                    Text("Unrestricted").tag(LiabilityMode.myFault)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(!bootstrap.canDisableGuardrails)

                Text(bootstrap.probationStatusText)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(
                        bootstrap.canDisableGuardrails
                            ? Color.chissPrimary.opacity(0.60)
                            : Color.white.opacity(0.40)
                    )
                    .lineLimit(2)
            }
        }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        VStack(spacing: 14) {
            // Utility row
            HStack(spacing: 8) {
                actionButton("Diagnostics", icon: "waveform.path.ecg") {
                    Task { await bootstrap.runGuidedDiagnostics() }
                }
                actionButton("Full Test", icon: "testtube.2") {
                    Task { await bootstrap.runFullHealthTest() }
                }
                actionButton("Reindex", icon: "arrow.clockwise") {
                    Task { await bootstrap.reindexCogneeMemory() }
                }

                actionButton("Export", icon: "square.and.arrow.up") {
                    Task { await bootstrap.exportSupportBundle() }
                }
            }

            // Divider
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.chissPrimary.opacity(0.0),
                            Color.chissPrimary.opacity(0.12),
                            Color.chissPrimary.opacity(0.0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)

            // Primary actions
            HStack(spacing: 12) {
                Button("Defer") {
                    bootstrap.deferSetup()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color.white.opacity(0.40))
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(
                    Capsule()
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )

                Spacer()

                Button(action: {
                    // Save provider keys before setup completes
                    saveProviderKeys()
                    Task { await bootstrap.completeOneClickSetup() }
                }) {
                    HStack(spacing: 8) {
                        if bootstrap.isWorking {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.55)
                                .tint(Color.white)
                        }
                        Text(bootstrap.isWorking ? "INITIALIZING" : "INITIALIZE")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(2)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.chissPrimary.opacity(0.35),
                                        Color.chissDeep.opacity(0.80)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(
                                Capsule()
                                    .stroke(Color.chissPrimary.opacity(0.40), lineWidth: 1)
                            )
                            .shadow(color: Color.chissPrimary.opacity(0.25 * glowPulse), radius: 12)
                    )
                }
                .buttonStyle(.plain)
                .disabled(bootstrap.isWorking)
            }
        }
    }

    // MARK: - Reusable Components

    private func terminalCard<Content: View>(label: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Card header
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Color.chissPrimary.opacity(0.45))
                Text(label)
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(2)
                    .foregroundColor(Color.chissPrimary.opacity(0.45))
                Spacer()
                // Angular accent
                Rectangle()
                    .fill(Color.chissPrimary.opacity(0.12))
                    .frame(width: 30, height: 1)
            }

            content()
        }
        .padding(14)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.30))
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.chissPrimary.opacity(0.08), lineWidth: 1)
                // Subtle top-edge highlight
                VStack {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.chissPrimary.opacity(0.0),
                                    Color.chissPrimary.opacity(0.06),
                                    Color.chissPrimary.opacity(0.0)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 1)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    Spacer()
                }
            }
        )
    }

    private func terminalToggle(_ label: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color.white.opacity(0.65))
        }
        .toggleStyle(.switch)
        .tint(Color.chissPrimary)
    }

    private func fieldLabel(_ text: String) -> some View {
        HStack(spacing: 4) {
            Rectangle()
                .fill(Color.chissPrimary.opacity(0.30))
                .frame(width: 2, height: 10)
            Text(text)
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.5)
                .foregroundColor(Color.white.opacity(0.35))
        }
    }

    private func actionButton(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundColor(Color.chissPrimary.opacity(0.70))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        Capsule()
                            .stroke(Color.chissPrimary.opacity(0.12), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(bootstrap.isWorking)
    }

    // MARK: - Step Helpers

    private func stepColor(_ state: ThrawnBootstrap.StepState) -> Color {
        switch state {
        case .pending: return Color.white.opacity(0.30)
        case .running: return Color(red: 0.95, green: 0.78, blue: 0.32)
        case .done:    return Color.chissPrimary
        case .failed:  return Color(red: 1.0, green: 0.45, blue: 0.45)
        }
    }

    private func stepStatusLabel(_ state: ThrawnBootstrap.StepState) -> String {
        switch state {
        case .pending: return "STANDBY"
        case .running: return "ACTIVE"
        case .done:    return "ONLINE"
        case .failed:  return "FAULT"
        }
    }
}

// MARK: - Shapes

/// Angular corner bracket — used as CIC terminal framing
private struct CornerBracket: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return p
    }
}

/// Diamond indicator shape
private struct Diamond: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        p.closeSubpath()
        return p
    }
}
