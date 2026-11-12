import StorageCore
import SwiftUI

/// Illustration, title, message, and an optional action, centered.
struct EmptyStateView: View {
    let illustration: Illustration
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            IllustrationView(illustration, size: 96)
            Text(title)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.sticker)
                    .frame(maxWidth: 260)
                    .padding(.top, 6)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }
}

/// Banner note on what the app may read and change.
struct SafetyNote: View {
    var text = "SimpleShrink reads your photo library and your free space. In Files, it sees only a folder you pick. It changes only what you approve, and nothing leaves your iPhone."

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            IllustrationView(.umbrella, size: 44)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
    }
}

/// Full-screen dimmed progress overlay for longer operations.
struct WorkingOverlay: View {
    let message: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.15).ignoresSafeArea()
            VStack(spacing: 14) {
                SketchSpinner(size: 36)
                Text(message)
                    .font(.hand(18))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 22)
            .sticker(padding: 0)
            .frame(maxWidth: 280)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The small mint PRO tag on anything that needs Pro.
struct ProTag: View {
    var body: some View {
        Text("PRO")
            .font(.caption2.weight(.heavy))
            .tracking(0.8)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Theme.mint, in: Capsule())
            .foregroundStyle(Color(hex: 0x1A1A17))
            .accessibilityLabel("Pro")
    }
}
