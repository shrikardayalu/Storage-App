import StorageCore
import SwiftUI
import UIKit

/// Build Plan step 9: how to restart this iPhone, with the steps for Face ID
/// or Home-button phones. Tapping "I'm Restarting Now" takes the free-space
/// baseline; the next open after the restart shows what came back.
struct RestartGuideView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var progress: CGFloat = 0
    @State private var hasHomeButton = RestartSteps.hasHomeButton()

    private var isReady: Bool { model.restartCoach.pending != nil }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.bold))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    steps
                    Text("Any iPhone: Settings \u{2192} General \u{2192} Shut Down works too.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Picker("This iPhone has", selection: $hasHomeButton) {
                        Text("Face ID").tag(false)
                        Text("Home button").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Steps for")
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 140)
            }
        }
        .background(PaperBackground())
        .safeAreaInset(edge: .bottom) { actionBar }
        .drawing($progress, duration: 2.4)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("worth a try")
                .font(.hand(20))
                .foregroundStyle(Theme.accent)
                .handwritten(progress, start: 0, length: 0.2)
            Text("Restart your iPhone")
                .font(.display(34))
                .boiling()
                .tracking(-1)
                .accessibilityAddTraits(.isHeader)
            Text("A restart gives iOS a chance to clear out temporary files it's been holding on to. Sometimes that frees a lot, sometimes very little. Storage App can't do it for you, but it measures what comes back.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(RestartSteps.steps(hasHomeButton: hasHomeButton).enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(index + 1)")
                        .font(.display(22))
                        .frame(width: 34, height: 34)
                        .background(Theme.mintSoft, in: Circle())
                        .overlay(Circle().strokeBorder(Theme.ink, lineWidth: 1.4))
                    Text(step)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 5)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .card(padding: 16)
    }

    private var actionBar: some View {
        VStack(spacing: 8) {
            if isReady {
                Label("Free space saved. Restart now, then open Storage App again.", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Done") { dismiss() }
                    .buttonStyle(.sticker)
            } else {
                Button("I'm Restarting Now") {
                    Task { await model.startRestart() }
                }
                .buttonStyle(.sticker)
                Text("Saves today's free space, so the next open can show what came back.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .background(.bar)
    }
}

/// The restart steps, by kind of iPhone.
enum RestartSteps {
    static func steps(hasHomeButton: Bool) -> [String] {
        [
            hasHomeButton
                ? "Press and hold the side button until the power-off slider appears."
                : "Press and hold the side button and either volume button until the power-off slider appears.",
            "Drag the slider, then wait about 30 seconds for your iPhone to turn off.",
            "Press and hold the side button until you see the Apple logo.",
            "Unlock your iPhone and open Storage App. It measures the space that came back.",
        ]
    }

    /// Phones with a Home button have no bottom safe area (no Home indicator).
    @MainActor
    static func hasHomeButton() -> Bool {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        return (window?.safeAreaInsets.bottom ?? 1) == 0
    }
}
