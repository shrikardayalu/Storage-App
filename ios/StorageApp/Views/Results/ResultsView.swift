import StorageCore
import SwiftUI

extension FreedSource {
    var title: String {
        switch self {
        case .photos: "Photos"
        case .videos: "Videos"
        case .files: "Files"
        case .guides: "Guides"
        case .restart: "Restart"
        }
    }

    var detail: String {
        switch self {
        case .photos: "Deleted, stills, bursts, duplicates"
        case .videos: "Compressed and trimmed"
        case .files: "From a folder you picked"
        case .guides: "WhatsApp, Messages, Settings"
        case .restart: "Measured after restarting"
        }
    }

    var illustration: Illustration {
        switch self {
        case .photos: .photo
        case .videos: .compress
        case .files: .stackLarge
        case .guides: .shieldCheck
        case .restart: .reset
        }
    }
}

/// Everything Storage App measured coming back, by action, checked against
/// the real change in free space since the first one (Build Plan step 11).
struct ResultsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmingReset = false
    @State private var progress: CGFloat = 0

    var body: some View {
        let freed = model.freed
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                totalCard(freed)
                breakdown(freed)
                if let now = model.deviceStorage, let change = freed.freeSpaceChange(now: now), let start = freed.start {
                    CheckCard(total: freed.total, change: change, start: start, now: now)
                }
                if !freed.counted.isEmpty {
                    history(freed)
                    Button("Start Counting Again", role: .destructive) { confirmingReset = true }
                        .buttonStyle(.soft)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(PaperBackground())
        .navigationTitle("Results")
        .navigationBarTitleDisplayMode(.inline)
        .drawing($progress, duration: 2.4)
        .refreshable { await model.refreshDeviceStorage() }
        .task { await model.refreshDeviceStorage() }
        .confirmationDialog("Start counting again?", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Clear Results", role: .destructive) { model.resetResults() }
        } message: {
            Text("This clears the totals here. Nothing on your iPhone changes.")
        }
    }

    private func totalCard(_ freed: FreedLedger) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(freed.total > 0 ? "measured, not guessed" : "nothing measured yet")
                .font(.hand(21))
                .foregroundStyle(Theme.accent)
                .handwritten(progress, start: 0, length: 0.2)
            Text("YOU'VE FREED")
                .font(.caption2.weight(.bold))
                .tracking(1.8)
                .foregroundStyle(.secondary)
            SizeText(bytes: freed.total, style: .largeTitle, unitStyle: .title2, precision: .twoDecimals)
                .accessibilityLabel("You've freed \(ByteFormatter.accessibilityString(freed.total, precision: .twoDecimals))")
            DrawnStroke(path: Sketch.scribble(width: 200, at: CGPoint(x: 6, y: 10), seed: 1400), design: CGSize(width: 220, height: 20), progress: progress, start: 0.3, length: 0.3)
                .stroke(freed.total > 0 ? Theme.mint : Theme.ink.opacity(0.2), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: 220, height: 20)
                .accessibilityHidden(true)
            Text(freed.total > 0
                 ? "Each figure is free space read right before the action and again after, so it's what really came back."
                 : "Clean up photos, videos or files, or follow a guide. Storage App reads free space before and after each one and adds it up here.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sticker(fill: Theme.mintSoft, radius: 24, padding: 0)
        .padding(.top, 12)
    }

    private func breakdown(_ freed: FreedLedger) -> some View {
        let largest = max(1, FreedSource.allCases.map { freed.total(for: $0) }.max() ?? 1)
        return VStack(alignment: .leading, spacing: 12) {
            Text("By action")
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            ForEach(FreedSource.allCases, id: \.self) { source in
                let bytes = freed.total(for: source)
                HStack(spacing: 14) {
                    IllustrationView(source.illustration, size: 44)
                        .opacity(bytes > 0 ? 1 : 0.45)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(source.title).font(.headline)
                            Spacer(minLength: 8)
                            Text(bytes > 0 ? ByteFormatter.string(bytes, precision: .twoDecimals) : "nothing yet")
                                .font(bytes > 0 ? .metric(.headline) : .footnote)
                                .monospacedDigit()
                                .foregroundStyle(bytes > 0 ? .primary : .tertiary)
                        }
                        GeometryReader { proxy in
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Theme.mint)
                                .frame(width: bytes > 0 ? max(6, proxy.size.width * CGFloat(Double(bytes) / Double(largest))) : 0)
                        }
                        .frame(height: 8)
                        .background(Theme.well, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        Text(source.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .card(padding: 14)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(source.title), \(bytes > 0 ? ByteFormatter.accessibilityString(bytes, precision: .twoDecimals) : "nothing yet")")
            }
        }
    }

    private func history(_ freed: FreedLedger) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Every action")
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(freed.counted) { entry in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title)
                                .font(.subheadline.weight(.semibold))
                            Text(entry.isOpen
                                 ? "\(entry.source.title) · \(entry.baseline.date.formatted(date: .abbreviated, time: .shortened)) · still measuring"
                                 : "\(entry.source.title) · \(entry.baseline.date.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Text("+" + ByteFormatter.string(entry.measuredBytes, precision: .twoDecimals))
                            .font(.metric(.subheadline))
                            .monospacedDigit()
                            .foregroundStyle(Theme.accent)
                    }
                    .accessibilityElement(children: .combine)
                    if entry.id != freed.counted.last?.id {
                        DashedRule()
                    }
                }
            }
            .onReceipt()
        }
    }
}

/// The total next to the real change in free space since the first action,
/// so the figure can be checked. Downloads, other apps and iOS move free space
/// too, so the two only match when nothing else happened in between.
private struct CheckCard: View {
    let total: Int64
    let change: Int64
    let start: StorageSnapshot
    let now: StorageSnapshot

    /// Within this, the two count as matching.
    private var tolerance: Int64 { max(FreedLedger.noiseFloor, total / 20) }
    private var matches: Bool { abs(change - total) <= tolerance }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Check it yourself")
                .font(.headline)
            row("Free before the first action", ByteFormatter.string(start.availableBytes, precision: .twoDecimals),
                caption: start.date.formatted(date: .abbreviated, time: .shortened))
            row("Free now", ByteFormatter.string(now.availableBytes, precision: .twoDecimals),
                caption: now.date.formatted(date: .omitted, time: .shortened))
            DashedRule()
            row("Real change", (change >= 0 ? "+" : "\u{2212}") + ByteFormatter.string(abs(change), precision: .twoDecimals), caption: nil)
            row("Counted above", "+" + ByteFormatter.string(total, precision: .twoDecimals), caption: nil)
            HStack(alignment: .top, spacing: 10) {
                InkCheck(isOn: matches, size: 22, tint: matches ? Theme.mint : Theme.tomato)
                Text(matches
                     ? "They match. Nothing else changed free space much since then."
                     : change > total
                        ? "Free space grew more than Storage App counted, from things it didn't do (iOS clearing caches, other apps)."
                        : "Free space grew less than counted. Something else used space since then, like downloads, new photos, or app updates.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 2)
        }
        .card(padding: 18)
    }

    private func row(_ title: String, _ value: String, caption: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline)
                if let caption {
                    Text(caption).font(.caption).foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 8)
            Text(value)
                .font(.metric(.subheadline))
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    let model = AppModel.preview()
    model.showSampleResults()
    return NavigationStack { ResultsView() }
        .environment(model)
}
