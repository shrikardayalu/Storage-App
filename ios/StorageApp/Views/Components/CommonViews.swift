import StorageCore
import SwiftUI

/// Small pill that marks everything on screen as simulated.
struct DemoBadge: View {
    var body: some View {
        Label("Demo Mode", systemImage: "flask")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Theme.mintSoft, in: Capsule())
            .accessibilityLabel("Demo Mode. All media is simulated.")
    }
}

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

/// A horizontal bar split into one segment per category, sized by storage.
struct StorageBar: View {
    let summary: LibrarySummary

    var body: some View {
        GeometryReader { proxy in
            let total = max(summary.total.bytes, 1)
            HStack(spacing: 3) {
                ForEach(MediaCategory.allCases) { category in
                    let bytes = summary[category].bytes
                    if bytes > 0 {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Theme.color(for: category))
                            .frame(width: max(6, (proxy.size.width - 6) * CGFloat(bytes) / CGFloat(total)))
                    }
                }
                if summary.total.bytes == 0 {
                    RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Theme.well)
                }
            }
        }
        .frame(height: 18)
        .padding(3)
        .background(Theme.well, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        MediaCategory.allCases
            .map { "\($0.title): \(ByteFormatter.accessibilityString(summary[$0].bytes))" }
            .joined(separator: ", ")
    }
}

/// Legend row for `StorageBar`.
struct StorageLegendRow: View {
    let category: MediaCategory
    let total: CategoryTotal

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 3).fill(Theme.color(for: category)).frame(width: 12, height: 12)
            Text(category.title)
            Text(total.count, format: .number)
                .foregroundStyle(.secondary)
            Spacer()
            Text(ByteFormatter.string(total.bytes))
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(category.title), \(total.count) items, \(ByteFormatter.accessibilityString(total.bytes))")
    }
}

/// Banner note reminding people nothing real is touched.
struct SafetyNote: View {
    var text = "Demo Mode uses generated sample media. Nothing on your iPhone is read, deleted, or compressed."

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

/// Full-screen dimmed progress overlay for simulated operations.
struct WorkingOverlay: View {
    let message: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.15).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                Text(message).font(.subheadline.weight(.medium))
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .accessibilityElement(children: .combine)
    }
}

extension MediaItem {
    /// Short VoiceOver description, e.g. "Video, 1.2 gigabytes, 2:03, March 4, 2026".
    var accessibilityDescription: String {
        var parts = [category.singularTitle, ByteFormatter.accessibilityString(currentBytes)]
        if let duration {
            parts.append(DurationFormatter.string(duration))
        }
        if isCompressed {
            parts.append("compressed")
        }
        parts.append(creationDate.formatted(date: .long, time: .omitted))
        return parts.joined(separator: ", ")
    }
}
