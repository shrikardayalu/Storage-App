import StorageCore
import SwiftUI

/// Demo status, sample-library choice, reset, and version.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var pendingScenario: DemoScenario?
    @State private var confirmingReset = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    IllustrationView(.beaker, size: 52)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Demo Mode is on")
                            .font(.headline)
                        Text("The app works on generated sample media. It never asks for access to your photos.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
            }

            Section {
                ForEach(DemoScenario.allCases) { scenario in
                    Button {
                        if scenario != model.scenario {
                            pendingScenario = scenario
                        }
                    } label: {
                        ScenarioRow(scenario: scenario, isCurrent: scenario == model.scenario)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(scenario == model.scenario ? .isSelected : [])
                }
            } header: {
                Text("Sample Library")
            } footer: {
                Text("Each sample library is generated the same way every time, so results are repeatable.")
            }

            Section {
                Button("Reset Demo Library", role: .destructive) {
                    confirmingReset = true
                }
                .disabled(!model.canResetDemo || model.isWorking)
            } footer: {
                Text("Restores \(model.scenario.title) to its original state and clears simulated deletions, compression, and selection.")
            }

            Section("About") {
                LabeledContent("Version", value: AppInfo.versionString)
                LabeledContent("Mode", value: "Demo (simulated data)")
                VStack(alignment: .leading, spacing: 6) {
                    Text("About Demo Mode")
                        .font(.subheadline.weight(.semibold))
                    Text("Every photo, video, and screenshot here is generated inside the app. Deleting or compressing only changes these samples. A future version will scan your real Photos library, with your permission, and always ask before changing anything.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Settings")
        .confirmationDialog(
            "Switch to \(pendingScenario?.title ?? "")?",
            isPresented: Binding(get: { pendingScenario != nil }, set: { if !$0 { pendingScenario = nil } }),
            titleVisibility: .visible,
            presenting: pendingScenario
        ) { scenario in
            Button("Switch Library") {
                Task { await model.resetDemo(to: scenario) }
            }
        } message: { _ in
            Text("Simulated changes to the current sample library will be discarded.")
        }
        .confirmationDialog("Reset the demo library?", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) {
                Task { await model.resetDemo() }
            }
        } message: {
            Text("Deleted and compressed sample items come back.")
        }
        .overlay {
            if model.isWorking {
                WorkingOverlay(message: "Preparing library…")
            }
        }
    }
}

private struct ScenarioRow: View {
    let scenario: DemoScenario
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 12) {
            IllustrationView(Illustration.forScenario(scenario), size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(scenario.title)
                    .font(.body.weight(.medium))
                Text(scenario.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if isCurrent {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }
}

enum AppInfo {
    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0.0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(version) (\(build))"
    }
}

#Preview {
    NavigationStack { SettingsView() }
        .environment(AppModel.preview())
}
