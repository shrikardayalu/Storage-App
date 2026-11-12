import AVFoundation
import AVKit
import StorageCore
import SwiftUI
import UIKit

/// Which items a tool's big button works on. All does everything the tool
/// suggests in one tap; Select starts with nothing ticked so the person chooses.
enum PickScope: String, CaseIterable, Identifiable {
    case all = "All"
    case select = "Select"

    var id: String { rawValue }
}

/// What a press-and-hold opens: one item, or a burst or set of copies to page through.
struct MediaPreview: Identifiable {
    let id = UUID()
    let items: [MediaItem]
    /// The item that was pressed.
    let start: MediaItem.ID
    var title: String?
    /// In a burst or a set of copies: the one being kept.
    var keeper: MediaItem.ID?
    /// Called when the person picks another one to keep.
    var pick: ((MediaItem.ID) -> Void)?

    init(_ item: MediaItem) {
        items = [item]
        start = item.id
    }

    init(items: [MediaItem], start: MediaItem.ID, title: String, keeper: MediaItem.ID?, pick: ((MediaItem.ID) -> Void)?) {
        self.items = items
        self.start = start
        self.title = title
        self.keeper = keeper
        self.pick = pick
    }
}

extension View {
    /// The All / Select switch in the top bar, the same on every tool.
    func scopePicker(_ scope: Binding<PickScope>, label: String, isShown: Bool = true, isDisabled: Bool = false) -> some View {
        toolbar {
            if isShown {
                ToolbarItem(placement: .principal) {
                    Picker(label, selection: scope) {
                        ForEach(PickScope.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                    .disabled(isDisabled)
                }
            }
        }
    }

    /// A tap does `tap`; pressing and holding does `hold`, with a small bump.
    /// Used on rows and thumbnails in place of a button, so a hold doesn't also count as a tap.
    func tapAndHold(isEnabled: Bool = true, tap: @escaping () -> Void, hold: @escaping () -> Void) -> some View {
        contentShape(Rectangle())
            // The tap comes first so the list still scrolls under a finger.
            .onTapGesture { if isEnabled { tap() } }
            .onLongPressGesture(minimumDuration: 0.35, maximumDistance: 14) {
                guard isEnabled else { return }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                hold()
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { if isEnabled { tap() } }
            .accessibilityAction(named: "Preview") { if isEnabled { hold() } }
    }

    /// Shows the preview window while `preview` is set.
    func mediaPreview(_ preview: Binding<MediaPreview?>) -> some View {
        sheet(item: preview) { MediaPreviewSheet(preview: $0) }
    }
}

/// The preview window: watch the video, play the Live Photo, look at the
/// photo, or swipe through a burst's shots. Nothing here changes anything
/// except which shot is marked to keep.
struct MediaPreviewSheet: View {
    let preview: MediaPreview
    @Environment(\.dismiss) private var dismiss
    @State private var current: MediaItem.ID
    @State private var keeper: MediaItem.ID?

    init(preview: MediaPreview) {
        self.preview = preview
        _current = State(initialValue: preview.start)
        _keeper = State(initialValue: preview.keeper)
    }

    private var item: MediaItem? { preview.items.first { $0.id == current } }
    private var index: Int { preview.items.firstIndex { $0.id == current } ?? 0 }

    var body: some View {
        VStack(spacing: 14) {
            header
            TabView(selection: $current) {
                ForEach(preview.items) { item in
                    PreviewPage(item: item, isActive: item.id == current)
                        .padding(.horizontal, 16)
                        .tag(item.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            if preview.items.count > 1 {
                strip
                if preview.pick != nil { keepButton }
            }
        }
        .padding(.top, 18)
        .padding(.bottom, 12)
        .background(PaperBackground())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(preview.title ?? item?.filename ?? "Preview")
                    .font(.display(22))
                    .tracking(-0.5)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .accessibilityAddTraits(.isHeader)
                if let item {
                    Text(Self.detail(item))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if preview.items.count > 1 {
                    Text("\(index + 1) of \(preview.items.count) · swipe to see the others")
                        .font(.hand(15))
                        .foregroundStyle(Theme.accent)
                }
            }
            Spacer(minLength: 8)
            Button("Done") { dismiss() }
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 20)
    }

    /// The shots in a row: tap one to jump to it. The kept one is circled.
    private var strip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 8) {
                    ForEach(preview.items) { item in
                        Button {
                            withAnimation(.snappy) { current = item.id }
                        } label: {
                            ItemThumbnail(id: item.id, side: 50)
                                .opacity(item.id == current ? 1 : 0.55)
                                .overlay {
                                    if item.id == keeper {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(Theme.accent, lineWidth: 3)
                                            .padding(-4)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .id(item.id)
                        .accessibilityLabel(item.filename)
                        .accessibilityValue(item.id == keeper ? "Kept" : "")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
            }
            .scrollIndicators(.hidden)
            .frame(height: 66)
            .onChange(of: current) { _, id in
                withAnimation(.snappy) { proxy.scrollTo(id, anchor: .center) }
            }
            .onAppear { proxy.scrollTo(current, anchor: .center) }
        }
    }

    private var keepButton: some View {
        Button(current == keeper ? "Keeping This One" : "Keep This One Instead") {
            keeper = current
            preview.pick?(current)
        }
        .buttonStyle(.sticker)
        .disabled(current == keeper)
        .padding(.horizontal, 20)
    }

    private static func detail(_ item: MediaItem) -> String {
        var parts = [item.creationDate.formatted(date: .abbreviated, time: .shortened)]
        if item.category == .video {
            parts.append("\(VideoTime.resolution(item.pixelWidth, item.pixelHeight)), \(VideoTime.string(item.duration ?? 0))")
        } else if item.traits.contains(.livePhoto) {
            parts.append("Live Photo")
        }
        parts.append(ByteFormatter.string(item.currentBytes, precision: .twoDecimals))
        return parts.joined(separator: " · ")
    }
}

/// One item in the preview window, shown the way its kind calls for.
private struct PreviewPage: View {
    let item: MediaItem
    let isActive: Bool

    var body: some View {
        Group {
            if item.category == .video {
                VideoPreview(id: item.id, isActive: isActive)
            } else if item.traits.contains(.livePhoto) {
                LivePhotoPlayer(id: item.id, isActive: isActive)
            } else {
                StillPreview(id: item.id)
            }
        }
        .aspectRatio(CGFloat(max(item.pixelWidth, 1)) / CGFloat(max(item.pixelHeight, 1)), contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.ink.opacity(0.8), lineWidth: 1.5))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A photo, big. Shows the small thumbnail until the full picture is ready.
struct StillPreview: View {
    let id: MediaItem.ID
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Theme.well
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                SketchSpinner(size: 28)
            }
        }
        .task(id: id) {
            image = PhotoThumbnailLoader.cached(id)
            image = await MediaPreviewLoader.image(for: id, side: 900) ?? image
        }
        .accessibilityHidden(true)
    }
}

/// A video with the usual player controls. Plays while it's the page on screen.
private struct VideoPreview: View {
    let id: MediaItem.ID
    let isActive: Bool
    @State private var player: AVPlayer?
    @State private var couldNotLoad = false

    var body: some View {
        ZStack {
            Color.black
            if let player {
                VideoPlayer(player: player)
            } else if couldNotLoad {
                VStack(spacing: 6) {
                    Image(systemName: "video.slash")
                        .font(.title2)
                    Text("Can't play this video right now.")
                        .font(.footnote)
                }
                .foregroundStyle(.white.opacity(0.85))
                .padding()
            } else {
                SketchSpinner(size: 28, tint: .white)
            }
        }
        .task(id: id) {
            guard player == nil else { return }
            guard let item = await VideoPreviewLoader.playerItem(for: id) else {
                couldNotLoad = true
                return
            }
            let loaded = AVPlayer(playerItem: item)
            player = loaded
            if isActive { loaded.play() }
        }
        .onChange(of: isActive) { _, active in
            if active { player?.play() } else { player?.pause() }
        }
        .onDisappear { player?.pause() }
    }
}
