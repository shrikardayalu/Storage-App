import StorageCore
import SwiftUI

/// Step 4: turn Live Photos in the test album into stills. Each still is the
/// same image with the same date, location, favorite and album; only the
/// short video goes, to Recently Deleted.
struct LivePhotoStillsView: View {
    @Environment(AppModel.self) private var model
    @State private var chosen: Set<MediaItem.ID> = []
    @State private var check: SafetyCheck?
    @State private var error: PhotoChangeError?
    @State private var confirming = false
    @State private var progress: CGFloat = 0
    @State private var didLoad = false

    private var livePhotos: [MediaItem] { model.convertibleLivePhotos }
    /// Items the safety check refused, such as ones also in another album.
    private var blocked: Set<MediaItem.ID> {
        guard let check else { return [] }
        return check.outsideTestAlbum.union(check.inOtherAlbums)
    }
    private var approved: Set<MediaItem.ID> { chosen.subtracting(blocked) }
    private var savedBytes: Int64 {
        livePhotos.filter { approved.contains($0.id) }.reduce(0) { $0 + $1.livePhotoVideoBytes }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                SketchCanvas(marks: GuideScenes.liveToStill, progress: progress)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity)
                    .sticker(radius: 26, padding: 8)
                    .rotationEffect(.degrees(-0.6))
                keeps
                list
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
        .safeAreaInset(edge: .bottom) { actionBar }
        .drawing($progress, duration: 3)
        .overlay {
            if model.isChanging { WorkingOverlay(message: "Making stills…") }
        }
        .confirmationDialog(
            "Turn \(countText) into stills?",
            isPresented: $confirming,
            titleVisibility: .visible
        ) {
            Button(approved.count == 1 ? "Make 1 Still" : "Make \(approved.count) Stills") {
                Task { await convert() }
            }
        } message: {
            Text("Each photo becomes a still that stays in your library, with its date, location, favorite and album. Only the old Live versions (photo plus video) go to Recently Deleted. You can recover them there for 30 days.")
        }
        .task {
            guard !didLoad else { return }
            didLoad = true
            chosen = Set(livePhotos.map(\.id))
            await runCheck()
        }
    }

    private var countText: String {
        approved.count == 1 ? "1 Live Photo" : "\(approved.count) Live Photos"
    }

    // MARK: Sections

    private var header: some View {
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
                SafetyLine(done: true, text: "The album", progress: progress, start: 0.76)
            }
            Text("Your stills stay in your library. Only the old Live versions go to Recently Deleted, so you'll see them there. SimpleShrink checks each still afterwards and shows you the result.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var list: some View {
        if livePhotos.isEmpty {
            EmptyStateView(
                illustration: .photo,
                title: "No Live Photos here",
                message: "Nothing in \u{201C}\(TestMode.albumName)\u{201D} is a Live Photo. Shots in a burst are left for the burst step."
            )
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("\(livePhotos.count) Live Photos in the test album")
                        .font(.headline)
                    Spacer()
                    Button(chosen.count == livePhotos.count ? "None" : "All") {
                        chosen = chosen.count == livePhotos.count ? [] : Set(livePhotos.map(\.id))
                    }
                    .font(.subheadline.weight(.semibold))
                }
                .padding(.bottom, 8)
                ForEach(livePhotos) { item in
                    LivePhotoRow(
                        item: item,
                        isOn: approved.contains(item.id),
                        blockedReason: blockedReason(item)
                    ) {
                        if chosen.contains(item.id) { chosen.remove(item.id) } else { chosen.insert(item.id) }
                    }
                    if item.id != livePhotos.last?.id { Divider() }
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

    private var actionBar: some View {
        VStack(spacing: 6) {
            Button {
                confirming = true
            } label: {
                Text(approved.isEmpty ? "Pick Live Photos" : (approved.count == 1 ? "Make 1 Still" : "Make \(approved.count) Stills"))
            }
            .buttonStyle(.sticker)
            .disabled(approved.isEmpty || check == nil || model.isChanging)
            Text(check == nil ? (error == nil ? "Checking the test album…" : "Fix the problem above to continue.") : "Stills stay in your library. Old Live versions go to Recently Deleted.")
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
        switch await model.safetyCheck(all) {
        case .success(let value):
            check = value
            error = nil
        case .failure(let failure):
            // A failed check leaves nothing approved, not the last check's result.
            check = nil
            error = failure
        }
    }

    private func convert() async {
        let ids = approved
        guard !ids.isEmpty else { return }
        if let failure = await model.convertToStills(approved: ids) {
            error = failure
            await runCheck()
        } else {
            chosen = Set(model.convertibleLivePhotos.map(\.id))
        }
    }
}

private struct LivePhotoRow: View {
    let item: MediaItem
    let isOn: Bool
    let blockedReason: String?
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                InkCheck(isOn: isOn, size: 24)
                    .opacity(blockedReason == nil ? 1 : 0.3)
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(blockedReason != nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.filename), saves \(ByteFormatter.accessibilityString(item.livePhotoVideoBytes, precision: .twoDecimals))")
        .accessibilityValue(blockedReason ?? (isOn ? "Picked" : "Not picked"))
        .accessibilityAddTraits(.isButton)
    }
}
