import StorageCore
import SwiftUI

/// Step 4: turn Live Photos in the library into stills. Each still is the
/// same image with the same date, location, favorite and album; only the
/// short video goes, to Recently Deleted.
///
/// It opens on All, which covers only the Live Photos that don't need to be
/// Live: people, pets, scenery, favorites and great shots are left as they
/// are. Select, in the top bar, lists every Live Photo with nothing ticked,
/// so the person chooses. Pressing and holding a photo plays it.
struct LivePhotoStillsView: View {
    @Environment(AppModel.self) private var model
    @State private var scope: PickScope = .all
    /// The Live Photos ticked in Select. All ignores it.
    @State private var chosen: Set<MediaItem.ID> = []
    @State private var check: SafetyCheck?
    @State private var error: PhotoChangeError?
    @State private var confirming = false
    @State private var progress: CGFloat = 0
    @State private var preview: MediaPreview?
    /// Stays up a moment after the check finishes, so the scribble can reach the end.
    @State private var showChecking = false

    private var livePhotos: [MediaItem] { model.convertibleLivePhotos }
    /// The ones a still would do for. Empty until the photos have been checked.
    private var suggested: [MediaItem] { model.suggestedLivePhotos ?? [] }
    /// Items the safety check refused, such as ones that are gone since the scan.
    private var blocked: Set<MediaItem.ID> {
        guard let check else { return [] }
        return check.missing
    }
    private var approved: [MediaItem] {
        let blocked = blocked
        switch scope {
        case .all: return suggested.filter { !blocked.contains($0.id) }
        case .select: return livePhotos.filter { chosen.contains($0.id) && !blocked.contains($0.id) }
        }
    }
    /// True until every Live Photo has been looked at. The rest of the library can still be measuring.
    private var isChecking: Bool { !model.liveCheckFinished }

    var body: some View {
        // Worked out once per redraw: a library can hold thousands of these.
        content(approved)
    }

    private func content(_ approved: [MediaItem]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(savedBytes: savedBytes(approved))
                SketchCanvas(marks: GuideScenes.liveToStill, progress: progress)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity)
                    .sticker(radius: 26, padding: 8)
                    .rotationEffect(.degrees(-0.6))
                keeps
                if showChecking { checking }
                list(approvedCount: approved.count)
                if let error {
                    Text(error.localizedDescription)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.tomato)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 130)
        }
        .background(PaperBackground())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .scopePicker($scope, label: "Which Live Photos to turn into stills", isShown: !livePhotos.isEmpty, isDisabled: model.isChanging)
        .safeAreaInset(edge: .bottom) { actionBar(approved) }
        .drawing($progress, duration: 3)
        .overlay {
            if model.isChanging { WorkingOverlay(message: "Making stills…") }
        }
        .confirmationDialog(
            "Turn \(approved.count == 1 ? "1 Live Photo" : "\(approved.count) Live Photos") into stills?",
            isPresented: $confirming,
            titleVisibility: .visible
        ) {
            Button(Self.buttonTitle(approved.count)) {
                Task { await convert(Set(approved.map(\.id))) }
            }
        } message: {
            Text("Each photo becomes a still that stays in your library, with its date, location, favorite and albums. Only the old Live versions (photo plus video) go to Recently Deleted. You can recover them there for 30 days.")
        }
        .mediaPreview($preview)
        // Looks at each photo once, to tell which ones are worth keeping Live.
        .task {
            showChecking = !model.liveCheckFinished && !livePhotos.isEmpty
            await model.findJunk()
        }
        .onChange(of: model.liveCheckFinished) { _, finished in
            guard !livePhotos.isEmpty else { showChecking = false; return }
            if !finished {
                showChecking = true
                return
            }
            Task {
                try? await Task.sleep(for: .milliseconds(450))
                if model.liveCheckFinished { showChecking = false }
            }
        }
        .task(id: livePhotos.map(\.id)) {
            chosen.formIntersection(livePhotos.map(\.id))
            await runCheck()
        }
    }

    private static func buttonTitle(_ count: Int) -> String {
        count == 1 ? "Make 1 Still" : "Make \(count) Stills"
    }

    // MARK: Sections

    /// While the check is still going, All shows the whole video portion. It settles to the suggested stills once every Live Photo has been looked at.
    private func savedBytes(_ approved: [MediaItem]) -> Int64 {
        let items = isChecking && scope == .all ? livePhotos : approved
        return items.reduce(Int64(0)) { $0 + $1.livePhotoVideoBytes }
    }

    private func header(savedBytes: Int64) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("same photo, minus the video")
                .font(.hand(20))
                .foregroundStyle(Theme.accent)
                .handwritten(progress, start: 0, length: 0.2)
            Text("Live Photos → stills")
                .font(.display(32))
                .boiling()
                .tracking(-1)
                .accessibilityAddTraits(.isHeader)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Saves about")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                SizeText(bytes: savedBytes, style: .title, unitStyle: .headline, precision: .twoDecimals)
                    .foregroundStyle(Theme.accent)
            }
            .padding(.top, 2)
        }
        .padding(.top, 8)
    }

    private var keeps: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Every still keeps")
                .font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                SafetyLine(done: true, text: "Its date", progress: progress, start: 0.55)
                SafetyLine(done: true, text: "Its location", progress: progress, start: 0.62)
                SafetyLine(done: true, text: "Favorite", progress: progress, start: 0.69)
                SafetyLine(done: true, text: "Its albums", progress: progress, start: 0.76)
            }
            Text("Your stills stay in your library. Only the old Live versions go to Recently Deleted, so you'll see them there. SimpleShrink checks each still afterwards and shows you the result.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var checking: some View {
        AnalysisMeter(
            progress: model.liveAnalysisProgress,
            caption: "Working out which Live Photos are worth keeping Live, on this iPhone. Nothing leaves it."
        )
    }

    @ViewBuilder
    private func list(approvedCount: Int) -> some View {
        let keep = model.liveKeepReasons ?? [:]
        // Select shows every Live Photo, the suggested ones first.
        let rows = scope == .all ? suggested : suggested + livePhotos.filter { keep[$0.id] != nil }
        let staying = livePhotos.count - suggested.count
        if livePhotos.isEmpty {
            EmptyStateView(
                illustration: .photo,
                title: "No Live Photos here",
                message: "Nothing in your library is a Live Photo. Shots in a burst are left for the burst step."
            )
        } else if rows.isEmpty {
            if !isChecking {
                EmptyStateView(
                    illustration: .shieldCheck,
                    title: "Nothing to suggest",
                    message: "Your \(livePhotos.count == 1 ? "Live Photo looks" : "\(livePhotos.count) Live Photos look") worth keeping Live. Switch to Select at the top to pick any yourself."
                )
            }
        } else {
            // Lazy: a library can hold thousands of these.
            LazyVStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(scope == .all
                         ? "\(suggested.count) \(suggested.count == 1 ? "Live Photo doesn't" : "Live Photos don't") need to be Live"
                         : "\(livePhotos.count) Live \(livePhotos.count == 1 ? "Photo" : "Photos")")
                        .font(.headline)
                    Spacer()
                    if scope == .select {
                        Text("\(approvedCount) picked")
                            .font(.hand(16))
                            .foregroundStyle(Theme.accent)
                    }
                }
                .padding(.bottom, 4)
                Text(scope == .all
                     ? "A still does fine for these. \(staying > 0 ? "\(staying) with people, pets, scenery or a favorite \(staying == 1 ? "stays" : "stay") Live. " : "")Switch to Select at the top to choose yourself. Press and hold a photo to play it."
                     : "Tick the ones to turn into stills. Press and hold a photo to play it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 6)
                if scope == .select {
                    HStack(spacing: 16) {
                        if !suggested.isEmpty {
                            Button("Tick suggested") { chosen.formUnion(suggested.map(\.id)) }
                        }
                        if !chosen.isEmpty {
                            Button("Clear") { chosen = [] }
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.bottom, 6)
                }
                ForEach(rows) { item in
                    let blockedReason = blockedReason(item)
                    LivePhotoRow(
                        item: item,
                        showsCheck: scope == .select,
                        isOn: chosen.contains(item.id) && blockedReason == nil,
                        stays: keep[item.id],
                        blockedReason: blockedReason
                    )
                    .tapAndHold(isEnabled: blockedReason == nil) {
                        if scope == .select {
                            if chosen.contains(item.id) { chosen.remove(item.id) } else { chosen.insert(item.id) }
                        } else {
                            preview = MediaPreview(item)
                        }
                    } hold: {
                        preview = MediaPreview(item)
                    }
                    if item.id != rows.last?.id { Divider() }
                }
            }
            .card(padding: 14)
        }
    }

    private func blockedReason(_ item: MediaItem) -> String? {
        guard let check else { return nil }
        if check.missing.contains(item.id) { return "not in your library any more" }
        return nil
    }

    private func actionBar(_ approved: [MediaItem]) -> some View {
        VStack(spacing: 6) {
            Button {
                confirming = true
            } label: {
                Text(approved.isEmpty ? "Pick Live Photos" : Self.buttonTitle(approved.count))
            }
            .buttonStyle(.sticker)
            .disabled(approved.isEmpty || check == nil || model.isChanging || (scope == .all && isChecking))
            Text(check == nil
                 ? (error == nil ? "Checking your library…" : "Fix the problem above to continue.")
                 : "Stills stay in your library. Old Live versions go to Recently Deleted.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .background(.bar)
    }

    // MARK: Actions

    /// Checks every Live Photo once, so ones that can't be touched are shown as such.
    private func runCheck() async {
        let all = Set(livePhotos.map(\.id))
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

    private func convert(_ ids: Set<MediaItem.ID>) async {
        guard !ids.isEmpty else { return }
        if let failure = await model.convertToStills(approved: ids) {
            error = failure
            await runCheck()
        }
    }
}

private struct LivePhotoRow: View {
    let item: MediaItem
    let showsCheck: Bool
    let isOn: Bool
    /// Why this one is better left Live, if it is.
    let stays: KeepReason?
    let blockedReason: String?

    var body: some View {
        HStack(spacing: 12) {
            if showsCheck {
                InkCheck(isOn: isOn, size: 24)
                    .opacity(blockedReason == nil ? 1 : 0.3)
            }
            ItemThumbnail(id: item.id, side: 46)
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
                    Text(item.creationDate.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let stays {
                        Text(stays == .notChecked ? "not checked yet" : "better Live: \(stays.note)")
                            .font(.hand(14))
                            .foregroundStyle(Theme.accent)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 1) {
                Text("−\(ByteFormatter.string(item.livePhotoVideoBytes, precision: .twoDecimals))")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(Theme.accent)
                Text("video")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .opacity(blockedReason == nil ? 1 : 0.6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.filename), saves \(ByteFormatter.accessibilityString(item.livePhotoVideoBytes, precision: .twoDecimals))")
        .accessibilityValue(blockedReason ?? (showsCheck ? (isOn ? "Picked" : "Not picked") : "Included"))
    }
}
