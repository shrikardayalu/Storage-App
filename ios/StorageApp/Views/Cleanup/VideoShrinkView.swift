import AVFoundation
import AVKit
import Observation
import StorageCore
import SwiftUI

/// Step 6: the videos in the library that can be made smaller, biggest first.
/// It opens on All, where one tap shrinks every video at the quality Smart
/// picks for each. Select, in the top bar, starts with nothing ticked so the
/// person chooses which ones. Tapping a video opens it to trim or pick a
/// quality by hand; pressing and holding plays it.
struct VideosView: View {
    @Environment(AppModel.self) private var model
    @State private var check: SafetyCheck?
    @State private var error: PhotoChangeError?
    @State private var progress: CGFloat = 0
    /// The videos ticked in Select. All ignores it.
    @State private var chosen: Set<MediaItem.ID> = []
    @State private var scope: PickScope = .all
    @State private var setting: BatchVideoQuality = .smart
    @State private var confirming = false
    /// The video opened to trim or pick a quality.
    @State private var opened: MediaItem?
    @State private var preview: MediaPreview?

    private var videos: [MediaItem] { model.shrinkableVideos }
    private var leftAlone: Int { model.videosLeftAlone }
    private var bestSaving: Int64 { model.videoSaving }
    /// Items the safety check refused, such as ones that are gone since the scan.
    private var blocked: Set<MediaItem.ID> {
        guard let check else { return [] }
        return check.missing
    }
    private var approved: [MediaItem] {
        let blocked = blocked
        return videos.filter { (scope == .all || chosen.contains($0.id)) && !blocked.contains($0.id) }
    }
    private func pick(_ item: MediaItem) -> SmartPick { VideoShrink.pick(setting, for: item) }
    private func saving(_ item: MediaItem) -> Int64 {
        VideoShrink.estimatedSaving(for: item, edit: VideoEdit(quality: pick(item).quality, trim: .full(item.duration ?? 0)))
    }

    var body: some View {
        // Worked out once per redraw: a library can hold thousands of videos.
        content(approved)
    }

    private func content(_ approved: [MediaItem]) -> some View {
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
                if !videos.isEmpty { qualityPicker }
                list(approvedCount: approved.count)
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
            .padding(.bottom, videos.isEmpty ? 40 : 140)
        }
        .background(PaperBackground())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .scopePicker($scope, label: "Which videos to shrink", isShown: !videos.isEmpty, isDisabled: model.isChanging)
        .navigationDestination(item: $opened) { VideoShrinkView(item: $0) }
        .mediaPreview($preview)
        .safeAreaInset(edge: .bottom) {
            if !videos.isEmpty { actionBar(approved) }
        }
        .drawing($progress, duration: 1.6)
        .overlay {
            if let batch = model.videoBatchProgress {
                WorkingOverlay(message: batch.done < batch.total
                    ? "Making smaller copies… \(batch.done + 1) of \(batch.total)"
                    : "Swapping in your smaller videos…")
            }
        }
        .confirmationDialog("Shrink \(approved.count == 1 ? "1 video" : "\(approved.count) videos")?", isPresented: $confirming, titleVisibility: .visible) {
            Button(Self.buttonTitle(approved.count)) { Task { await shrink(approved) } }
        } message: {
            Text("SimpleShrink makes a smaller copy of each one first and only swaps the ones that come out clearly smaller. Copies keep their date, location and favorite. The originals go to Recently Deleted, where you can recover them for 30 days. Keep the app open while it works.")
        }
        .task(id: videos.map(\.id)) {
            chosen.formIntersection(videos.map(\.id))
            await runCheck()
        }
    }

    private static func buttonTitle(_ count: Int) -> String {
        count == 1 ? "Shrink 1 Video" : "Shrink \(count) Videos"
    }

    // MARK: Sections

    private var qualityPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(scope == .all ? "Shrink all at once" : "Shrink the ones you pick")
                .font(.headline)
            HStack(spacing: 8) {
                ForEach(BatchVideoQuality.allCases) { option in
                    Button {
                        setting = option
                    } label: {
                        HStack(spacing: 4) {
                            if option == .smart { Image(systemName: "sparkles").font(.caption.weight(.bold)) }
                            Text(option.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(setting == option ? Theme.mintSoft : Theme.surface, in: Capsule())
                        .overlay(Capsule().strokeBorder(setting == option ? Theme.accent : Theme.ink.opacity(0.35), lineWidth: setting == option ? 2 : 1))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(setting == option ? [.isButton, .isSelected] : .isButton)
                }
            }
            Text(setting.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card(padding: 14)
    }

    @ViewBuilder
    private func list(approvedCount: Int) -> some View {
        let lastID = videos.last?.id
        if videos.isEmpty {
            EmptyStateView(
                illustration: .compress,
                title: "No videos to shrink",
                message: "Nothing in your library is a video that can be made smaller."
            )
        } else {
            // Lazy: a library can hold hundreds of these.
            LazyVStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("\(videos.count) \(videos.count == 1 ? "video" : "videos")")
                        .font(.headline)
                    Spacer()
                    if scope == .select {
                        Text("\(approvedCount) picked")
                            .font(.hand(16))
                            .foregroundStyle(Theme.accent)
                        if !chosen.isEmpty {
                            Button("Clear") { chosen = [] }
                                .font(.subheadline.weight(.semibold))
                                .padding(.leading, 6)
                        }
                    }
                }
                .padding(.bottom, 4)
                Text(scope == .all
                     ? "Every video is included. Switch to Select at the top to choose which ones. Tap a video to trim it or pick its quality yourself, or press and hold to play it."
                     : "Tick the videos to shrink. Tap a video to trim it or pick its quality yourself, or press and hold to play it.")
                    .fixedSize(horizontal: false, vertical: true)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 6)
                ForEach(videos) { item in
                    let blockedReason = blockedReason(item)
                    HStack(spacing: 10) {
                        if scope == .select {
                            Button {
                                if chosen.contains(item.id) { chosen.remove(item.id) } else { chosen.insert(item.id) }
                            } label: {
                                InkCheck(isOn: chosen.contains(item.id) && blockedReason == nil, size: 24)
                                    .opacity(blockedReason == nil ? 1 : 0.3)
                                    .frame(width: 32, height: 52)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(blockedReason != nil)
                            .accessibilityLabel("Include \(item.filename)")
                            .accessibilityValue(chosen.contains(item.id) ? "Picked" : "Not picked")
                        }
                        VideoRow(item: item, pick: pick(item), saving: saving(item), blockedReason: blockedReason)
                            .tapAndHold(isEnabled: blockedReason == nil) {
                                if check != nil { opened = item }
                            } hold: {
                                preview = MediaPreview(item)
                            }
                    }
                    if item.id != lastID { Divider() }
                }
            }
            .card(padding: 14)
        }
    }

    private func actionBar(_ approved: [MediaItem]) -> some View {
        let batchSaving = approved.reduce(Int64(0)) { $0 + saving($1) }
        return VStack(spacing: 6) {
            Button {
                confirming = true
            } label: {
                Text(approved.isEmpty
                     ? "Pick Videos"
                     : "\(Self.buttonTitle(approved.count)), Save ~\(ByteFormatter.string(batchSaving, precision: .twoDecimals))")
            }
            .buttonStyle(.sticker)
            .disabled(approved.isEmpty || check == nil || model.isChanging)
            Text(check == nil
                 ? (error == nil ? "Checking your library…" : "Fix the problem above to continue.")
                 : "One tap: copies first, then one swap. Originals go to Recently Deleted.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .background(.bar)
    }

    private func blockedReason(_ item: MediaItem) -> String? {
        guard let check else { return nil }
        if check.missing.contains(item.id) { return "not in your library any more" }
        return nil
    }

    // MARK: Actions

    private func runCheck() async {
        let all = Set(videos.map(\.id))
        guard !all.isEmpty else { return }
        switch await model.albumCheck(all) {
        case .success(let value):
            check = value
            error = nil
        case .failure(let failure):
            // A failed check leaves nothing approved, not the last check's result.
            check = nil
            error = failure
        }
    }

    private func shrink(_ approved: [MediaItem]) async {
        let qualities = Dictionary(uniqueKeysWithValues: approved.map { ($0.id, pick($0).quality) })
        guard !qualities.isEmpty else { return }
        error = nil
        if let failure = await model.shrinkVideos(qualities) {
            error = failure
            await runCheck()
        }
    }
}

private struct VideoRow: View {
    let item: MediaItem
    let pick: SmartPick
    let saving: Int64
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
                    Text("\(pick.quality.title.lowercased()) · \(pick.reason)")
                        .font(.hand(14))
                        .foregroundStyle(Theme.accent)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 1) {
                Text(ByteFormatter.string(item.currentBytes, precision: .twoDecimals))
                    .font(.subheadline.weight(.bold).monospacedDigit())
                Text("about −\(ByteFormatter.string(saving, precision: .twoDecimals))")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
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
            Text("The smaller copy goes in your library with the same date, location and favorite. The original goes to Recently Deleted, where you can recover it for 30 days.")
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
            } else if player.couldNotLoad {
                // Shrinking still works; only the preview is missing.
                VStack(spacing: 6) {
                    Image(systemName: "video.slash")
                        .font(.title2)
                    Text("Can't play a preview of this video right now.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.white.opacity(0.85))
                .padding()
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
                            Text(option.detail(width: item.pixelWidth, height: item.pixelHeight))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 6)
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(Self.savingText(item.currentBytes - estimate))
                                .font(.subheadline.weight(.bold).monospacedDigit())
                                .foregroundStyle(Theme.accent)
                            Text("\u{2248} \(ByteFormatter.string(estimate, precision: .twoDecimals)) after")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
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
            savedLine(saved: item.currentBytes - after, measured: prepared != nil)
            if let prepared {
                Text("Your copy is ready, \(VideoTime.string(prepared.newDuration)) long. Nothing in Photos has changed yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .sticker(fill: prepared == nil ? Theme.surface : Theme.mintSoft, padding: 14)
    }

    /// The headline figure: how much space this frees, and what share of the video that is.
    private func savedLine(saved: Int64, measured: Bool) -> some View {
        let share = item.currentBytes > 0 ? Double(max(saved, 0)) / Double(item.currentBytes) : 0
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            if saved > 0 {
                Text("\(measured ? "Saves" : "Saves about") \(ByteFormatter.string(saved, precision: .twoDecimals))")
                    .font(.headline)
                Spacer(minLength: 6)
                Text("\(Int((share * 100).rounded()))% smaller")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.accent)
            } else {
                Text("No space saved at this setting. Try Smaller file or trim it.")
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
    }

    /// "Saves 120.40 MB", or "No saving" when there's nothing to gain.
    static func savingText(_ bytes: Int64) -> String {
        bytes > 0 ? "Saves \(ByteFormatter.string(bytes, precision: .twoDecimals))" : "No saving"
    }

    private var actionBar: some View {
        VStack(spacing: 6) {
            if let prepared {
                Button(prepared.savedBytes > 0
                       ? "Replace Video, Save \(ByteFormatter.string(prepared.savedBytes, precision: .twoDecimals))"
                       : "Replace Video") { confirming = true }
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
    /// Photos couldn't hand over the video, e.g. it's in iCloud and the phone is offline.
    private(set) var couldNotLoad = false
    var trim: VideoTrim?
    @ObservationIgnored private var observer: Any?

    nonisolated init() {}

    func load(_ id: MediaItem.ID) async {
        guard player == nil else { return }
        guard let item = await VideoPreviewLoader.playerItem(for: id) else {
            couldNotLoad = true
            return
        }
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
