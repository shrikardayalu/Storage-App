import StorageCore
import SwiftUI
import UIKit

/// Everything the test album scan found, biggest first, with totals per group.
struct LibraryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        content
            .scrollContentBackground(.hidden)
            .background(PaperBackground())
            .navigationTitle(model.isSelecting ? "Pick to Delete" : "Library")
            .toolbar {
                if model.albumScan?.total.count ?? 0 > 0 {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(model.isSelecting ? "Cancel" : "Select") {
                            withAnimation(.snappy) {
                                if model.isSelecting { model.clearSelection() }
                                model.isSelecting.toggle()
                            }
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Scan Again") {
                        Task { await model.scanTestAlbum() }
                    }
                    .disabled(model.isScanning || model.isChanging)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if model.isSelecting {
                    SelectionBar()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .overlay {
                if model.isScanning {
                    WorkingOverlay(message: "Scanning test album…")
                }
            }
            .sheet(isPresented: $model.isReviewing, onDismiss: { model.presentPendingGuide() }) {
                CleanupReviewView()
            }
    }

    @ViewBuilder
    private var content: some View {
        if let scan = model.albumScan {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        SizeText(bytes: scan.total.bytes, style: .largeTitle, unitStyle: .title2, precision: .twoDecimals)
                        Text("\(scan.total.count.formatted()) items · \(ScanSource.title(for: model.photoAccess)) · scanned \(scan.date.formatted(date: .omitted, time: .shortened))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                }

                Section {
                    ForEach(ScanGroup.allCases) { option in
                        GroupRow(group: option, total: scan[option], burstCount: scan.burstCount, isSelected: model.libraryGroup == option) {
                            model.libraryGroup = model.libraryGroup == option ? nil : option
                        }
                    }
                } header: {
                    Text("Groups")
                } footer: {
                    Text("Each item is in one of the first five groups. Big Formats overlaps them.")
                }

                let items = scan.items(in: model.libraryGroup)
                Section {
                    if items.isEmpty {
                        Text("Nothing in \(model.libraryGroup?.title ?? "this album").")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(items) { item in
                        if model.isSelecting {
                            Button {
                                model.toggleSelection(item.id)
                            } label: {
                                ScanItemRow(item: item, isSelected: model.selection.contains(item.id))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(model.selection.contains(item.id) ? [.isButton, .isSelected] : .isButton)
                        } else {
                            ScanItemRow(item: item)
                        }
                    }
                } header: {
                    HStack {
                        Text(model.libraryGroup.map { "\($0.title), biggest first" } ?? "Everything, biggest first")
                        Spacer()
                        if model.isSelecting, !items.isEmpty {
                            let all = items.allSatisfy { model.selection.contains($0.id) }
                            Button(all ? "Deselect All" : "Select All") {
                                for item in items where model.selection.contains(item.id) == all {
                                    model.toggleSelection(item.id)
                                }
                            }
                            .font(.caption.weight(.semibold))
                            .textCase(nil)
                        }
                    }
                }
            }
        } else {
            VStack(spacing: 0) {
                EmptyStateView(
                    illustration: .photo,
                    title: "Nothing scanned yet",
                    message: "Scan the \u{201C}\(TestMode.albumName)\u{201D} album to see what takes up space. The app only reads it.",
                    actionTitle: model.isScanning ? nil : "Scan Test Album",
                    action: { Task { await model.scanTestAlbum() } }
                )
                if let error = model.scanError {
                    ScanErrorView(error: error)
                        .padding(.horizontal, 32)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}

/// Pinned under the list while picking: what's picked, and the way to review it.
private struct SelectionBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let items = model.selectedItems
        let bytes = items.reduce(Int64(0)) { $0 + $1.currentBytes }
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 1) {
                Text(items.isEmpty ? "Tap to pick" : "\(items.count) picked")
                    .font(.hand(19))
                Text(ByteFormatter.string(bytes, precision: .twoDecimals))
                    .font(.metric(.title3))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy, value: bytes)
            }
            Spacer(minLength: 8)
            Button("Review") { model.isReviewing = true }
                .buttonStyle(.sticker)
                .frame(width: 150)
                .disabled(items.isEmpty)
        }
        .sticker(radius: 22, padding: 14)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

/// Where a scan's items came from, for the summary lines.
enum ScanSource {
    static func title(for access: PhotoAccess) -> String {
        access == .limited ? "photos you picked" : "\u{201C}\(TestMode.albumName)\u{201D}"
    }
}

/// A failed scan's reason, with a way to fix access when that's the problem.
struct ScanErrorView: View {
    let error: PhotoScanError
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(error.localizedDescription)
                .font(.footnote)
                .foregroundStyle(Theme.tomato)
                .fixedSize(horizontal: false, vertical: true)
            if error == .accessDenied, let url = URL(string: UIApplication.openSettingsURLString) {
                Button("Open Settings") { openURL(url) }
                    .font(.footnote.weight(.semibold))
            }
        }
    }
}

private struct GroupRow: View {
    let group: ScanGroup
    let total: CategoryTotal
    let burstCount: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.title).font(.body.weight(.medium))
                    Text(countText).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(ByteFormatter.string(total.bytes, precision: .twoDecimals))
                    .font(.metric(.headline))
                    .monospacedDigit()
                Image(systemName: isSelected ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    .foregroundStyle(isSelected ? Theme.accent : Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(group.title), \(countText), \(ByteFormatter.accessibilityString(total.bytes, precision: .twoDecimals))")
        .accessibilityHint(isSelected ? "Shows everything again." : "Shows only \(group.title).")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var countText: String {
        let items = "\(total.count.formatted()) \(total.count == 1 ? "item" : "items")"
        return group == .bursts && total.count > 0 ? "\(items) in \(burstCount) \(burstCount == 1 ? "burst" : "bursts")" : items
    }
}

private struct ScanItemRow: View {
    let item: MediaItem
    /// Non-nil in selection mode.
    var isSelected: Bool?

    var body: some View {
        HStack(spacing: 12) {
            if let isSelected {
                InkCheck(isOn: isSelected, size: 26, tint: Theme.tomato)
            }
            PhotoThumbnail(localIdentifier: item.id)
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.filename)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(ByteFormatter.string(item.currentBytes, precision: .twoDecimals))
                .font(.subheadline.monospacedDigit())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.filename), \(details), \(ByteFormatter.accessibilityString(item.currentBytes, precision: .twoDecimals))")
    }

    private var details: String {
        var parts = [ScanGroup.kind(of: item).title]
        if ScanGroup.isBigFormat(item) { parts.append(bigFormatLabel) }
        if let duration = item.duration { parts.append(DurationFormatter.string(duration)) }
        parts.append(item.creationDate.formatted(date: .abbreviated, time: .omitted))
        return parts.joined(separator: " · ")
    }

    private var bigFormatLabel: String {
        switch item.format {
        case .proRAW, .proRes: return item.format.displayName
        default: return item.traits.contains(.slowMotion) ? "Slo-mo" : "4K"
        }
    }
}

/// The item's real thumbnail from Photos, with a neutral placeholder while it loads.
private struct PhotoThumbnail: View {
    let localIdentifier: String
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Theme.well
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .task(id: localIdentifier) {
            image = await PhotoThumbnailLoader.image(for: localIdentifier, side: 52)
        }
        .accessibilityHidden(true)
    }
}
