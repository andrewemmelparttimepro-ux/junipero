import SwiftUI

struct SetupWizardView: View {
    @EnvironmentObject var bootstrap: JuniperoBootstrap

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Junipero One-Click Setup")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(Color.white.opacity(0.95))

            Text("OpenClaw runs automatically at login. Optional Ollama fallback keeps chat free/local when provider APIs are unavailable.")
                .font(.system(size: 13))
                .foregroundColor(Color.white.opacity(0.82))

            Picker("Mode", selection: $bootstrap.setupMode) {
                ForEach(JuniperoBootstrap.SetupMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if bootstrap.setupMode == .bringYourOwn {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Provider Token")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.9))
                    SecureField("Paste your OpenClaw/provider token", text: $bootstrap.providerToken)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.95)))

                    Text("Primary Model")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.9))
                    TextField("anthropic/claude-sonnet-4-6", text: $bootstrap.providerModel)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.95)))

                    Text("Token is stored securely in macOS Keychain.")
                        .font(.system(size: 11))
                        .foregroundColor(Color.white.opacity(0.72))
                }
            }

            Toggle("Enable Ollama local fallback", isOn: $bootstrap.enableOllamaFallback)
                .toggleStyle(.switch)
                .foregroundColor(.white.opacity(0.9))

            if bootstrap.enableOllamaFallback {
                Toggle("Auto-download kimi-k2.5 if missing", isOn: $bootstrap.autoInstallKimi)
                    .toggleStyle(.switch)
                    .foregroundColor(.white.opacity(0.85))
            }

            if let error = bootstrap.errorText {
                Text(error)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(red: 1.0, green: 0.86, blue: 0.86))
            } else {
                Text(bootstrap.statusText)
                    .font(.system(size: 12))
                    .foregroundColor(Color.white.opacity(0.8))
            }

            Text(bootstrap.diagnosticsSummary)
                .font(.system(size: 11))
                .foregroundColor(Color.white.opacity(0.74))
                .lineLimit(3)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(JuniperoBootstrap.SetupStep.allCases) { step in
                    HStack(spacing: 8) {
                        Image(systemName: icon(for: bootstrap.stateForStep(step)))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(color(for: bootstrap.stateForStep(step)))
                        Text(step.rawValue)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.86))
                    }
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.10))
            )

            HStack(spacing: 12) {
                Button(action: {
                    Task { await bootstrap.runGuidedDiagnostics() }
                }) {
                    Text("Run Diagnostics")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.16))
                        )
                }
                .buttonStyle(.plain)
                .disabled(bootstrap.isWorking)

                if bootstrap.enableOllamaFallback && bootstrap.missingOllamaModel {
                    Button(action: {
                        Task { await bootstrap.installMissingFallbackModel() }
                    }) {
                        Text("Fix Missing Model")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(Color(red: 0.22, green: 0.48, blue: 0.80))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(bootstrap.isWorking)
                }

                Button(action: {
                    Task { await bootstrap.runFullHealthTest() }
                }) {
                    Text("Run Full Test")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.16))
                        )
                }
                .buttonStyle(.plain)
                .disabled(bootstrap.isWorking)
            }

            HStack(spacing: 12) {
                Button("Later") {
                    bootstrap.deferSetup()
                }
                .buttonStyle(.plain)
                .foregroundColor(.white.opacity(0.75))

                Spacer()

                Button(action: {
                    Task { await bootstrap.completeOneClickSetup() }
                }) {
                    HStack(spacing: 8) {
                        if bootstrap.isWorking {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                        Text(bootstrap.isWorking ? "Setting up…" : "Set Up Now")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(Color(red: 0.22, green: 0.48, blue: 0.80))
                    )
                }
                .buttonStyle(.plain)
                .disabled(bootstrap.isWorking)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 560)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.28, blue: 0.54),
                    Color(red: 0.08, green: 0.20, blue: 0.40),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private func icon(for state: JuniperoBootstrap.StepState) -> String {
        switch state {
        case .pending: return "circle"
        case .running: return "clock.fill"
        case .done: return "checkmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        }
    }

    private func color(for state: JuniperoBootstrap.StepState) -> Color {
        switch state {
        case .pending: return Color.white.opacity(0.5)
        case .running: return Color(red: 0.98, green: 0.78, blue: 0.32)
        case .done: return Color(red: 0.50, green: 0.92, blue: 0.55)
        case .failed: return Color(red: 1.0, green: 0.55, blue: 0.55)
        }
    }
}
