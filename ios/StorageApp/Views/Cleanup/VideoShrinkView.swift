import AVFoundation
import AVKit
import Observation
import StorageCore
import SwiftUI

/// Step 6: the videos in the test album that can be made smaller, biggest first.
struct VideosView: View {
    @Environment(AppModel.self) private var model
    @State private var check: SafetyCheck?
    @State private var error: PhotoChangeError?
    @State private var progress: CGFloat = 0

    private var videos: [MediaItem] { model.shrinkableVideos }
    private var leftAlone: Int {
        (model.albumScan?.items.filter { $0.category == .video }.count ?? 0) - videos.count
    }
    private var bestSaving: Int64 {
        videos.reduce(0) { $0 + VideoShrink.estimatedSaving(for: $1, edit: VideoEdit(quality: .hd1080, trim: .full($1.duration ?? 0))) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("smaller videos, same memories")
                        .font(.hand(20))
                        .foregroundStyle(Theme.accent)
                        .handwritten(progress, start: 0, length: 0.3)
                    Text("Shrink videos")
                        .font(.display(32))
                        .boiling()
                        .tracking(-1)
                        .accessibilityAddTraits(.isHeader)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("Up to about")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.secondary)
                        SizeText(bytes: bestSaving, style: .title, unitStyle: .headline, precision: .twoDecimals)
                            .foregroundStyle(Theme.accent)
                    }
                    .padding(.top, 2)
                }
                .padding(.top, 8)
                Text("Pick a video, choose its quality and trim the start or end. Storage App makes a smaller copy first, so you see its real size before anything in Photos changes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                list
                if leftAlone > 0 {
                    Text("\(leftAlone == 1 ? "1 video is" : "\(leftAlone) videos are") left alone: slo-mo, Cinematic and ProRes stay editable, and very small videos aren't worth it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let error {
                    Text(error.localizedDescription)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.tomato)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .background(PaperBackground())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .drawing($progress, duration: 1.6)
        .task(id: videos.map(\.id)) { await runCheck() }
    }

    @ViewBuilder
    private var list: some View {
        if videos.isEmpty {
            EmptyStateView(
                illustration: .compress,
                title: "No videos to shrink",
                message: "Nothing in \u{201C}\(TestMode.albumName)\u{201D} is a video that can be made smaller."
            )
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(videos) { item in
                    let blocked = blockedReason(item)
                    NavigationLink {
                        VideoShrinkView(item: item)
                    } label: {
                        VideoRow(item: item, blockedReason: blocked)
                    }
                    .buttonStyle(.plain)
                    .disabled(blocked != nil || check == nil)
                    if item.id != videos.last?.id { Divider() }
                }
            }
            .card(padding: 14)
        }
    }

    private func blockedReason(_ item: MediaItem) -> String? {
        guard let check else { return nil }
        if check.inOtherAlbums.contains(item.id) { return "also in another album, so it's left alone" }
        if check.outsideTestAlbum.contains(item.id) { return "not in the test album any more" }
        return nil
    }

    private func runCheck() async {
        let all = Set(videos.map(\.id))
        guard !all.isEmpty else { return }
        switch await model.safetyCheck(all) {
        case .success(let value):
            check = value
            error = nil
        case .failure(let failure):
            error = failure
        }
    }
}

private struct VideoRow: View {
    let item: MediaItem
    let blockedReason: String?

    var body: some View {
        HStack(spacing: 12) {
            ItemThumbnail(id: item.id, side: 52)
                .overlay(alignment: .bottomTrailing) {
                    Text(VideoTime.string(item.duration ?? 0))
                        .font(.system(size: 10, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(3)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.filename)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let blockedReason {
                    Text(blockedReason)
                        .font(.hand(14))
                        .foregroundStyle(Theme.tomato)
                } else {
                    Text("\(VideoTime.resolution(item.pixelWidth, item.pixelHeight)) · \(item.creationDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 1) {
                Text(ByteFormatter.string(item.currentBytes, precision: .twoDecimals))
                    .font(.subheadline.weight(.bold).monospacedDigit())
                Text("up to −\(ByteFormatter.string(VideoShrink.estimatedSaving(for: item, edit: VideoEdit(quality: .hd1080, trim: .full(item.duration ?? 0))), precision: .twoDecimals))")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .opacity(blockedReason == nil ? 1 : 0.6)
        .accessibilityElement(children: .combine)
    }
}

/// One video: watch it, trim the start and end, pick a quality, make a
/// smaller copy and see its real size, then swap it in.
struct VideoShrinkView: View {
    let item: MediaItem

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var quality: VideoQuality = .sameQuality
    @State private var trim: VideoTrim
    @State private var player = TrimPlayer()
    @State private var prepared: PreparedVideo?
    @State private var error: PhotoChangeError?
    @State private var confirming = false
    @State private var replaced = false

    init(item: MediaItem) {
        self.item = item
        _trim = State(initialValue: .full(item.duration ?? 0))
    }

    private var duration: TimeInterval { item.duration ?? 0 }
    private var edit: VideoEdit { VideoEdit(quality: quality, trim: trim) }
    private var isTrimmed: Bool { !trim.isFull(of: duration) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.filename)
                        .font(.display(26))
                        .boiling()
                        .tracking(-0.8)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .accessibilityAddTraits(.isHeader)
                    Text("\(VideoTime.resolution(item.pixelWidth, item.pixelHeight)) · \(VideoTime.string(duration)) · \(item.creationDate.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
                preview
                trimSection
                qualitySection
                sizes
                if let error {
                    Text(error.localizedDescription)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.tomato)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 150)
        }
        .background(PaperBackground())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { actionBar }
        .overlay {
            if model.isChanging {
                WorkingOverlay(message: prepared == nil ? "Making a smaller copy…" : "Swapping in your smaller video…")
            }
        }
        .confirmationDialog("Replace with the smaller video?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Replace Video") { Task { await replace() } }
        } message: {
            Text("The smaller copy goes in your library and the test album with the same date, location and favorite. The original goes to Recently Deleted, where you can recover it for 30 days.")
        }
        .task {
            await player.load(item.id)
            player.trim = trim
        }
        .onChange(of: edit) { _, _ in
            player.trim = trim
            // A copy made with other settings no longer matches what's shown.
            discardCopy()
            error = nil
        }
        .onDisappear {
            player.pause()
            if !replaced { discardCopy() }
        }
    }

    // MARK: Sections

    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black)
            if let avPlayer = player.player {
                VideoPlayer(player: avPlayer)
            } else {
                ProgressView().tint(.white)
            }
        }
        .aspectRatio(CGFloat(max(item.pixelWidth, 1)) / CGFloat(max(item.pixelHeight, 1)), contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: 280)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.ink, lineWidth: 1.5))
    }

    private var trimSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Trim")
                    .font(.headline)
                Spacer()
                if isTrimmed {
                    Button("Keep all") { trim = .full(duration) }
                        .font(.subheadline.weight(.semibold))
                }
            }
            TrimBar(duration: duration, trim: $trim) { player.seek(to: $0) }
                .frame(height: 48)
            HStack {
                Text(VideoTime.string(trim.start))
                Spacer()
                Text(isTrimmed ? "keeping \(VideoTime.string(trim.length))" : "keeping all")
                    .font(.hand(15))
                    .foregroundStyle(isTrimmed ? Theme.accent : Color.secondary)
                Spacer()
                Text(VideoTime.string(trim.end))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .card(padding: 14)
    }

    private var qualitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quality")
                .font(.headline)
            ForEach(VideoQuality.allCases) { option in
                let estimate = VideoShrink.estimatedBytes(for: item, edit: VideoEdit(quality: option, trim: trim))
                Button {
                    quality = option
                } label: {
                    HStack(spacing: 12) {
                        InkCheck(isOn: quality == option, size: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.title)
                                .font(.subheadline.weight(.semibold))
                            Text(option.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 6)
                        Text("≈ \(ByteFormatter.string(estimate, precision: .twoDecimals))")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(Theme.accent)
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(quality == option ? [.isButton, .isSelected] : .isButton)
            }
        }
        .card(padding: 14)
    }

    private var sizes: some View {
        let after = prepared?.newBytes ?? VideoShrink.estimatedBytes(for: item, edit: edit)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("BEFORE")
                        .font(.caption2.weight(.bold))
                        .tracking(1.4)
                        .foregroundStyle(.secondary)
                    SizeText(bytes: item.currentBytes, style: .title2, unitStyle: .subheadline, precision: .twoDecimals)
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.headline)
                    .foregroundStyle(.tertiary)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(prepared == nil ? "AFTER, ABOUT" : "AFTER, MEASURED")
                        .font(.caption2.weight(.bold))
                        .tracking(1.4)
                        .foregroundStyle(prepared == nil ? Color.secondary : Theme.accent)
                    SizeText(bytes: after, style: .title2, unitStyle: .subheadline, precision: .twoDecimals)
                        .foregroundStyle(Theme.accent)
                }
            }
            if let prepared {
                Text("Your copy is ready: \(ByteFormatter.string(prepared.savedBytes, precision: .twoDecimals)) smaller, \(VideoTime.string(prepared.newDuration)) long. Nothing in Photos has changed yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .sticker(fill: prepared == nil ? Theme.surface : Theme.mintSoft, padding: 14)
    }

    private var actionBar: some View {
        VStack(spacing: 6) {
            if let prepared {
                Button("Replace Video") { confirming = true }
                    .buttonStyle(.sticker)
                    .disabled(model.isChanging)
                Button("Throw away the copy") { discardCopy() }
                    .font(.footnote.weight(.semibold))
                    .disabled(model.isChanging)
                    .accessibilityHint("Saves \(ByteFormatter.accessibilityString(prepared.savedBytes, precision: .twoDecimals)) if you replace instead")
            } else {
                Button("Make Smaller Copy") { Task { await prepare() } }
                    .buttonStyle(.sticker)
                    .disabled(model.isChanging || duration < VideoTrim.minimumLength)
                Text("Makes a copy first so you see its real size. Nothing in Photos changes yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .background(.bar)
    }

    // MARK: Actions

    private func prepare() async {
        player.pause()
        error = nil
        switch await model.prepareVideo(item.id, edit: edit) {
        case .success(let copy):
            prepared = copy
        case .failure(let failure):
            error = failure
        }
    }

    private func replace() async {
        guard let prepared else { return }
        player.pause()
        if let failure = await model.replaceVideo(with: prepared) {
            error = failure
        } else {
            replaced = true
            self.prepared = nil
            dismiss()
        }
    }

    private func discardCopy() {
        guard let copy = prepared else { return }
        prepared = nil
        Task { await model.discard(copy) }
    }
}

/// Plays a video and keeps playback inside the trimmed part.
@MainActor
@Observable
final class TrimPlayer {
    private(set) var player: AVPlayer?
    var trim: VideoTrim?
    @ObservationIgnored private var observer: Any?

    nonisolated init() {}

    func load(_ id: MediaItem.ID) async {
        guard player == nil, let item = await VideoPreviewLoader.playerItem(for: id) else { return }
        let player = AVPlayer(playerItem: item)
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 10), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.keepInside(time.seconds) }
        }
        self.player = player
    }

    func seek(to seconds: TimeInterval) {
        player?.pause()
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func pause() {
        player?.pause()
    }

    /// Jumps back to the start of the kept part when playback leaves it.
    private func keepInside(_ seconds: TimeInterval) {
        guard let trim, let player, player.rate != 0 else { return }
        if seconds >= trim.end || seconds < trim.start - 0.2 {
            player.pause()
            player.seek(to: CMTime(seconds: trim.start, preferredTimescale: 600))
        }
    }
}

/// A strip with a handle at each end of the part to keep.
private struct TrimBar: View {
    let duration: TimeInterval
    @Binding var trim: VideoTrim
    /// Called with the time under a handle while it's dragged.
    let scrub: (TimeInterval) -> Void

    private let handle: CGFloat = 18
    private static let space = "trimBar"

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width - handle * 2, 1)
            let x = { (t: TimeInterval) in handle + CGFloat(t / max(duration, 0.01)) * width }
            let time = { (px: CGFloat) in TimeInterval((px - handle) / width) * duration }
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.well)
                    .padding(.horizontal, handle)
                Rectangle()
                    .fill(Theme.mintSoft)
                    .frame(width: max(x(trim.end) - x(trim.start), 0))
                    .offset(x: x(trim.start))
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Theme.accent, lineWidth: 3)
                    .frame(width: max(x(trim.end) - x(trim.start), 0) + handle * 2)
                    .offset(x: x(trim.start) - handle)
                knob(at: x(trim.start) - handle, label: "Start", value: trim.start) { px in
                    trim = VideoTrim(start: time(px), end: trim.end).clamped(to: duration)
                    scrub(trim.start)
                }
                knob(at: x(trim.end), label: "End", value: trim.end) { px in
                    trim = VideoTrim(start: trim.start, end: time(px)).clamped(to: duration)
                    scrub(trim.end)
                }
            }
            .coordinateSpace(name: Self.space)
            .frame(height: geo.size.height)
        }
    }

    /// `move` gets the finger's position along the bar.
    private func knob(at offset: CGFloat, label: String, value: TimeInterval, move: @escaping (CGFloat) -> Void) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Theme.accent)
            .overlay(Capsule().fill(.white).frame(width: 3, height: 16))
            .frame(width: handle)
            .offset(x: offset)
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space)).onChanged { value in
                move(value.location.x)
            })
            .accessibilityElement()
            .accessibilityLabel("\(label) of the part to keep")
            .accessibilityValue(VideoTime.string(value))
            .accessibilityAdjustableAction { direction in
                let step: TimeInterval = direction == .increment ? 1 : -1
                trim = (label == "Start"
                    ? VideoTrim(start: trim.start + step, end: trim.end)
                    : VideoTrim(start: trim.start, end: trim.end + step)).clamped(to: duration)
            }
    }
}

/// Video lengths and resolutions as people say them.
enum VideoTime {
    /// "0:42", "12:05", "1:02:10".
    static func string(_ seconds: TimeInterval) -> String {
        let total = Int(max(seconds, 0).rounded())
        let (h, m, s) = (total / 3600, total / 60 % 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// "4K", "1080p", "720p", or the pixel size for anything else.
    static func resolution(_ width: Int, _ height: Int) -> String {
        switch min(width, height) {
        case 2000...: "4K"
        case 1000..<2000: "1080p"
        case 700..<1000: "720p"
        default: "\(width)×\(height)"
        }
    }
}
