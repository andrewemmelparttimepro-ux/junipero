import SwiftUI

struct SetupWizardView: View {
    @EnvironmentObject var bootstrap: HermesBootstrap

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Junipero Setup")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(JuniperoTheme.textPrimary)

            Text("Hermes Agent powers your AI assistant. Junipero will install and manage it automatically.")
                .font(.system(size: 13))
                .foregroundColor(JuniperoTheme.textSecondary)

            // Status
            if let error = bootstrap.errorText {
                Text(error)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(JuniperoTheme.statusError)
            } else {
                Text(bootstrap.statusText)
                    .font(.system(size: 12))
                    .foregroundColor(JuniperoTheme.textSecondary)
            }

            Text(bootstrap.diagnosticsSummary)
                .font(.system(size: 11))
                .foregroundColor(JuniperoTheme.textTertiary)
                .lineLimit(3)

            // Step indicators
            VStack(alignment: .leading, spacing: 6) {
                ForEach(HermesBootstrap.SetupStep.allCases) { step in
                    HStack(spacing: 8) {
                        Image(systemName: stepIcon(for: bootstrap.stateForStep(step)))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(stepColor(for: bootstrap.stateForStep(step)))
                        Text(step.rawValue)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(JuniperoTheme.textSecondary)
                    }
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(JuniperoTheme.backgroundSurface)
            )

            // Capability mode
            VStack(alignment: .leading, spacing: 8) {
                Text("Capability Mode")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(JuniperoTheme.textSecondary)
                Picker("Capability Mode", selection: Binding(
                    get: { bootstrap.liabilityMode },
                    set: { bootstrap.setLiabilityMode($0) }
                )) {
                    Text("I'm an idiot").tag(LiabilityMode.idiot)
                    Text("It's my fault").tag(LiabilityMode.myFault)
                }
                .pickerStyle(.segmented)
                .disabled(!bootstrap.canDisableGuardrails)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(JuniperoTheme.backgroundSurface)
            )

            // Action buttons
            HStack(spacing: 12) {
                Button(action: {
                    Task { await bootstrap.runDiagnostics() }
                }) {
                    Text("Run Diagnostics")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(JuniperoTheme.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(JuniperoTheme.backgroundSurface))
                }
                .buttonStyle(.plain)
                .disabled(bootstrap.isWorking)

                Button(action: {
                    Task { await bootstrap.exportSupportBundle() }
                }) {
                    Text("Support")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(JuniperoTheme.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(JuniperoTheme.backgroundSurface))
                }
                .buttonStyle(.plain)
                .disabled(bootstrap.isWorking)
            }

            HStack(spacing: 12) {
                Button("Later") {
                    bootstrap.deferSetup()
                }
                .buttonStyle(.plain)
                .foregroundColor(JuniperoTheme.textTertiary)

                Spacer()

                Button(action: {
                    Task { await bootstrap.completeSetup() }
                }) {
                    HStack(spacing: 8) {
                        if bootstrap.isWorking {
                            ProgressView().scaleEffect(0.7)
                        }
                        Text(bootstrap.isWorking ? "Setting up..." : "Set Up Now")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(JuniperoTheme.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        Capsule().fill(
                            LinearGradient(
                                colors: [JuniperoTheme.copper, JuniperoTheme.copperDark],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    )
                    .shadow(color: JuniperoTheme.copper.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .buttonStyle(.plain)
                .disabled(bootstrap.isWorking)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 560)
        .background(JuniperoTheme.backgroundPrimary)
    }

    private func stepIcon(for state: HermesBootstrap.StepState) -> String {
        switch state {
        case .pending: return "circle"
        case .running: return "clock.fill"
        case .done: return "checkmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        }
    }

    private func stepColor(for state: HermesBootstrap.StepState) -> Color {
        switch state {
        case .pending: return JuniperoTheme.textTertiary
        case .running: return JuniperoTheme.statusWarning
        case .done: return JuniperoTheme.statusOnline
        case .failed: return JuniperoTheme.statusError
        }
    }
}
