import StorageCore
import SwiftUI

/// Simulated metadata for one item. Looks the item up by ID so it reflects
/// changes, and closes itself if the item is deleted.
struct MediaDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let itemID: MediaItem.ID

    var body: some View {
        NavigationStack {
            Group {
                if let item = model.item(withID: itemID) {
                    details(for: item)
                } else {
                    EmptyStateView(illustration: .trash, title: "Item removed", message: "This demo item is no longer in the library.")
                }
            }
            .navigationTitle(model.item(withID: itemID)?.category.singularTitle ?? "Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func details(for item: MediaItem) -> some View {
        List {
            Section {
                MediaThumbnail(item: item)
                    .aspectRatio(CGFloat(item.pixelWidth) / CGFloat(item.pixelHeight), contentMode: .fit)
                    .frame(maxHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }

            Section("File") {
                LabeledContent("Name", value: item.filename)
                LabeledContent("Format", value: item.format.displayName)
                LabeledContent("Created", value: item.creationDate.formatted(date: .long, time: .shortened))
                LabeledContent("Dimensions", value: "\(item.pixelWidth) × \(item.pixelHeight)")
                if let duration = item.duration {
                    LabeledContent("Duration", value: DurationFormatter.string(duration))
                } else {
                    LabeledContent("Resolution", value: String(format: "%.1f MP", item.megapixels))
                }
            }

            Section("Storage") {
                LabeledContent("Current size", value: ByteFormatter.string(item.currentBytes))
                if item.isCompressed {
                    LabeledContent("Original size", value: ByteFormatter.string(item.originalBytes))
                    LabeledContent("Saved", value: ByteFormatter.string(item.savedBytes))
                }
                LabeledContent("Compression", value: compressionStatus(for: item))
            }

            Section {
                Button(model.isSelected(item) ? "Remove from Selection" : "Select for Cleanup") {
                    model.toggleSelection(item)
                }
                .tint(Theme.accent)
            } footer: {
                Text("This is a generated demo item, not a file from your iPhone.")
            }
        }
    }

    private func compressionStatus(for item: MediaItem) -> String {
        if let level = item.compressionLevel {
            return "Compressed (\(level.title))"
        }
        if let reason = CompressionModel.unsupportedReason(for: item) {
            return reason.shortLabel
        }
        return "Supported"
    }
}

#Preview {
    let model = AppModel.preview(.typical)
    return MediaDetailView(itemID: model.items[3].id)
        .environment(model)
}
