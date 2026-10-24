import StorageCore
import SwiftUI

/// Review the current selection and choose to simulate compression or deletion.
struct CleanupReviewView: View {
    @Environment(AppModel.self) private var model
    @Environment(PurchaseStore.self) private var purchases
    @Environment(\.dismiss) private var dismiss

    @State private var level: CompressionLevel = .balanced
    @State private var confirmingDelete = false
    @State private var confirmingCompress = false
    @State private var showingPaywall = false
    @State private var result: CleanupResult?

    var body: some View {
        NavigationStack {
            Group {
                if let result {
                    CleanupResultView(result: result, onDone: { dismiss() })
                } else if model.selection.isEmpty {
                    EmptyStateView(
                        illustration: .photo,
                        title: "Nothing selected",
                        message: "Select photos, videos, or screenshots in the Library to review them here.",
                        actionTitle: "Go to Library",
                        action: {
                            model.selectedTab = .library
                            model.isSelecting = true
                            dismiss()
                        }
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    review
                }
            }
            .background(Theme.background)
            .navigationTitle(result == nil ? "Review Cleanup" : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if result == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                }
            }
            .overlay {
                if model.isWorking {
                    WorkingOverlay(message: "Simulating…")
                }
            }
        }
        .interactiveDismissDisabled(model.isWorking)
        .fullScreenCover(isPresented: $showingPaywall) {
            PaywallFlow()
        }
    }

    private var review: some View {
        let items = model.selectedItems
        let plan = CompressionPlan(items: items, level: level)
        let totalBytes = model.selectedBytes
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SelectionSummaryCard(items: items, totalBytes: totalBytes)

                CompressionCard(plan: plan, level: $level) {
                    // Shrinking is Pro; deleting stays free. No-op while the paywall is off.
                    if purchases.requiresPro {
                        showingPaywall = true
                    } else {
                        confirmingCompress = true
                    }
                }

                DeletionCard(count: items.count, bytes: totalBytes) {
                    confirmingDelete = true
                }

                SafetyNote()
            }
            .padding(20)
        }
        .confirmationDialog(
            "Compress \(plan.eligibleCount.formatted()) demo items?",
            isPresented: $confirmingCompress,
            titleVisibility: .visible
        ) {
            Button("Simulate \(level.title) Compression") {
                Task {
                    result = await model.compressSelected(level: level)
                }
            }
        } message: {
            Text("Sizes in the demo library will drop by about \(ByteFormatter.string(plan.savedBytes)). No real photos or videos are compressed.")
        }
        .confirmationDialog(
            "Delete \(items.count.formatted()) demo items?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete from Demo Library", role: .destructive) {
                Task {
                    result = await model.deleteSelected()
                }
            }
        } message: {
            Text("They'll be removed from the sample library only. Nothing on your iPhone is deleted, and you can undo this.")
        }
    }
}

/// Count, size, and per-category breakdown of the selection.
private struct SelectionSummaryCard: View {
    let items: [MediaItem]
    let totalBytes: Int64

    var body: some View {
        let byCategory = LibrarySummary(items: items)
        VStack(alignment: .leading, spacing: 12) {
            Text("\(items.count.formatted()) items selected")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            SizeText(bytes: totalBytes, style: .largeTitle, unitStyle: .title2)
            HStack(spacing: 8) {
                ForEach(MediaCategory.allCases) { category in
                    let total = byCategory[category]
                    if total.count > 0 {
                        CategoryChip(category: category, count: total.count)
                    }
                }
            }
        }
        .card(padding: 18)
    }
}

private struct CategoryChip: View {
    let category: MediaCategory
    let count: Int

    var body: some View {
        HStack(spacing: 4) {
            IllustrationView(Illustration.forCategory(category), size: 20)
            Text("\(count.formatted()) \(category.title.lowercased())")
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Theme.well, in: Capsule())
    }
}

/// Level picker, before/after sizes, and anything that can't be compressed.
private struct CompressionCard: View {
    let plan: CompressionPlan
    @Binding var level: CompressionLevel
    let onCompress: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeading(illustration: .compress, title: "Compress", subtitle: "Keep everything, just smaller.")

            Picker("Compression level", selection: $level) {
                ForEach(CompressionLevel.allCases) { level in
                    Text(level.title).tag(level)
                }
            }
            .pickerStyle(.segmented)
            Text(level.detail)
                .font(.caption)
                .foregroundStyle(.secondary)

            if plan.hasWork {
                HStack(alignment: .center, spacing: 10) {
                    sizeColumn("Before", bytes: plan.bytesBefore)
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                    sizeColumn("After (est.)", bytes: plan.bytesAfter)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Saves")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(ByteFormatter.string(plan.savedBytes))
                            .font(.metric(.title3))
                            .foregroundStyle(Theme.accent)
                    }
                    .accessibilityElement(children: .combine)
                }
                .monospacedDigit()
            }

            if !plan.skipped.isEmpty {
                SkippedList(plan: plan)
            }

            Button(action: onCompress) {
                Text(plan.hasWork ? "Simulate Compression (\(plan.eligibleCount.formatted()))" : "Nothing to Compress")
            }
            .buttonStyle(.sticker)
            .disabled(!plan.hasWork)

            Text("Simulation only. Estimates come from a simple size model; no real files are compressed.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .card(padding: 18)
    }

    private func sizeColumn(_ title: String, bytes: Int64) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(ByteFormatter.string(bytes))
                .font(.headline)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Explains which selected items compression skips and why.
private struct SkippedList: View {
    let plan: CompressionPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                IllustrationView(.lock, size: 26)
                Text(plan.hasWork
                     ? "\(plan.skippedCount.formatted()) items will be skipped"
                     : "None of the selected items can be compressed at this level")
                    .font(.subheadline.weight(.semibold))
            }
            ForEach(plan.skipped, id: \.reason) { group in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(group.count.formatted()) · \(group.reason.shortLabel)")
                        .font(.caption.weight(.semibold))
                    Text(group.reason.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.well.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct DeletionCard: View {
    let count: Int
    let bytes: Int64
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeading(illustration: .trash, title: "Delete", subtitle: "Remove them from the demo library.")
            HStack {
                Text("Recovers")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(ByteFormatter.string(bytes))
                    .font(.metric(.title3))
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
            Button(action: onDelete) {
                Text("Simulate Deletion (\(count.formatted()))")
            }
            .buttonStyle(.stickerDestructive)
            Text("You'll be asked to confirm. Deletion can be undone.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .card(padding: 18)
    }
}

private struct CardHeading: View {
    let illustration: Illustration
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            IllustrationView(illustration, size: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    let model = AppModel.preview(.typical)
    model.reviewCleanup()
    return CleanupReviewView()
        .environment(model)
        .environment(PurchaseStore())
}
