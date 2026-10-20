import StorageCore
import SwiftUI

/// Dashboard: how much space the demo library could free, and where it is.
struct HomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if !model.hasLoaded {
                    ProgressView("Loading demo library…")
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else if model.summary.total.count == 0 {
                    EmptyStateView(
                        illustration: .emptyBox,
                        title: "This demo library is empty",
                        message: "Pick a different sample library in Settings to explore cleanup.",
                        actionTitle: "Open Settings",
                        action: { model.selectedTab = .settings }
                    )
                    .card()
                } else {
                    PotentialSavingsCard()
                    if !model.savings.isEmpty {
                        RecoveredCard()
                    }
                    StorageOverviewCard(summary: model.summary)
                    categorySection
                }

                SafetyNote()
                    .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            IllustrationView(.phoneSparkle, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text("Storage App")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                Text(model.scenario.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            DemoBadge()
        }
        .padding(.top, 12)
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Where the space is")
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            CategoryCard(
                illustration: .video,
                title: "Large Videos",
                subtitle: "\(ByteFormatter.string(LibrarySummary.largeVideoThreshold)) or more",
                total: model.summary.largeVideos
            ) { model.showLibrary(filter: .largeVideos) }
            CategoryCard(
                illustration: .screenshot,
                title: "Screenshots",
                subtitle: "Usually safe to clear",
                total: model.summary[.screenshot]
            ) { model.showLibrary(filter: .screenshots) }
            CategoryCard(
                illustration: .photo,
                title: "Photos",
                subtitle: "Compress to save space",
                total: model.summary[.photo]
            ) { model.showLibrary(filter: .photos) }
        }
    }
}

/// The headline figure: screenshots plus estimated compression savings.
private struct PotentialSavingsCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let summary = model.summary
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Potential space to recover")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    SizeText(bytes: summary.potentialSavings, style: .largeTitle, unitStyle: .title2)
                    Squiggle()
                        .stroke(Theme.mint, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                        .frame(width: 120, height: 7)
                        .accessibilityHidden(true)
                }
                Spacer(minLength: 8)
                IllustrationView(.piggy, size: 76)
            }

            VStack(alignment: .leading, spacing: 4) {
                breakdownRow("Clear screenshots", bytes: summary.screenshotBytes)
                breakdownRow("Compress photos and videos (est.)", bytes: summary.compressionSavings)
            }
            .font(.footnote)

            Button(action: model.reviewCleanup) {
                Text(model.selection.isEmpty ? "Review Suggestions" : "Review \(model.selection.count) Selected")
            }
            .buttonStyle(.sticker)
            .padding(.top, 2)
            .accessibilityHint(model.selection.isEmpty ? "Selects all screenshots and large videos for review." : "")
        }
        .sticker(padding: 18)
    }

    private func breakdownRow(_ title: String, bytes: Int64) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(ByteFormatter.string(bytes)).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

/// What simulated cleanup has recovered so far, with undo.
private struct RecoveredCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 14) {
            IllustrationView(.shieldCheck, size: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text("Recovered in this demo")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(ByteFormatter.string(model.savings.totalBytes))
                    .font(.metric(.title2))
                    .monospacedDigit()
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if model.canUndo {
                Button("Undo") {
                    Task { await model.undoLastChange() }
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.bordered)
                .tint(Theme.accent)
                .disabled(model.isWorking)
            }
        }
        .card()
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        var parts: [String] = []
        if model.savings.deletedCount > 0 { parts.append("\(model.savings.deletedCount) deleted") }
        if model.savings.compressedCount > 0 { parts.append("\(model.savings.compressedCount) compressed") }
        return parts.joined(separator: " · ")
    }
}

private struct StorageOverviewCard: View {
    let summary: LibrarySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Simulated library")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    SizeText(bytes: summary.total.bytes, style: .title, unitStyle: .headline)
                }
                Spacer()
                Text("\(summary.total.count.formatted()) items")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            StorageBar(summary: summary)
            VStack(spacing: 8) {
                ForEach(MediaCategory.allCases) { category in
                    StorageLegendRow(category: category, total: summary[category])
                }
            }
        }
        .card(padding: 18)
    }
}

private struct CategoryCard: View {
    let illustration: Illustration
    let title: String
    let subtitle: String
    let total: CategoryTotal
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                IllustrationView(illustration, size: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(ByteFormatter.string(total.bytes))
                        .font(.metric(.headline))
                        .monospacedDigit()
                    Text("\(total.count.formatted()) items")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(.primary)
            .card(padding: 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(total.count) items, \(ByteFormatter.accessibilityString(total.bytes))")
        .accessibilityHint("Shows these items in the library.")
        .accessibilityAddTraits(.isButton)
    }
}

#Preview("Typical") {
    NavigationStack { HomeView() }
        .environment(AppModel.preview(.typical))
}

#Preview("Empty") {
    NavigationStack { HomeView() }
        .environment(AppModel.preview(.empty))
}
