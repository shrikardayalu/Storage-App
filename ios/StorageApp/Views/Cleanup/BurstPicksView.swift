import StorageCore
import SwiftUI

/// Step 5: keep the best shot of each burst in the test album and move the
/// rest to Recently Deleted. The person picks the keeper; the camera's own
/// pick is chosen to start with.
struct BurstPicksView: View {
    @Environment(AppModel.self) private var model
    /// Burst ID → the shot to keep. A burst missing here is skipped.
    @State private var keepers: [String: MediaItem.ID] = [:]
    @State private var check: SafetyCheck?
    @State private var error: PhotoChangeError?
    @State private var confirming = false
    @State private var progress: CGFloat = 0
    @State private var didLoad = false

    private var bursts: [Burst] { model.bursts }
    /// Shots the safety check refused, such as ones also in another album.
    private var blocked: Set<MediaItem.ID> {
        guard let check else { return [] }
        return check.outsideTestAlbum.union(check.inOtherAlbums)
    }
    /// The bursts that will be cleaned: picked, and with no shot the check refused.
    private var approved: [String: MediaItem.ID] {
        keepers.filter { burstID, _ in
            bursts.first { $0.id == burstID }.map { burst in
                !burst.shots.contains { blocked.contains($0.id) }
            } ?? false
        }
    }
    private var removeCount: Int {
        bursts.filter { approved[$0.id] != nil }.reduce(0) { $0 + $1.shots.count - 1 }
    }
    private var savedBytes: Int64 {
        bursts.reduce(0) { total, burst in
            approved[burst.id].map { total + burst.savedBytes(keeping: $0) } ?? total
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                SketchCanvas(marks: GuideScenes.burstPick, progress: progress)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity)
                    .sticker(radius: 26, padding: 8)
                    .rotationEffect(.degrees(0.6))
                Text("Tap the shot you want to keep in each burst. The other shots go to Recently Deleted, where you can recover them for 30 days.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
            if model.isChanging { WorkingOverlay(message: "Keeping your picks…") }
        }
        .confirmationDialog(
            "Keep \(keepCountText) and remove \(removeCountText)?",
            isPresented: $confirming,
            titleVisibility: .visible
        ) {
            Button(removeCount == 1 ? "Remove 1 Shot" : "Remove \(removeCount) Shots", role: .destructive) {
                Task { await clean() }
            }
        } message: {
            Text("Your picks stay in your library. The other shots go to Recently Deleted. You can recover them there for 30 days.")
        }
        .task {
            guard !didLoad else { return }
            didLoad = true
            keepers = Self.suggested(bursts)
            await runCheck()
        }
    }

    private var keepCountText: String {
        approved.count == 1 ? "1 shot" : "\(approved.count) shots"
    }

    private var removeCountText: String {
        removeCount == 1 ? "1 other" : "\(removeCount) others"
    }

    private static func suggested(_ bursts: [Burst]) -> [String: MediaItem.ID] {
        Dictionary(uniqueKeysWithValues: bursts.map { ($0.id, $0.suggestedKeeper) })
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("one keeper per burst")
                .font(.hand(20))
                .foregroundStyle(Theme.accent)
                .handwritten(progress, start: 0, length: 0.2)
            Text("Best shot of each burst")
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

    @ViewBuilder
    private var list: some View {
        if bursts.isEmpty {
            EmptyStateView(
                illustration: .stackSmall,
                title: "No bursts here",
                message: "Nothing in \u{201C}\(TestMode.albumName)\u{201D} is a burst with more than one shot."
            )
        } else {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(bursts) { burst in
                    BurstCard(
                        burst: burst,
                        keeper: keepers[burst.id],
                        blockedReason: blockedReason(burst),
                        pick: { keepers[burst.id] = $0 },
                        toggle: {
                            keepers[burst.id] = keepers[burst.id] == nil ? burst.suggestedKeeper : nil
                        }
                    )
                }
            }
        }
    }

    private func blockedReason(_ burst: Burst) -> String? {
        guard let check else { return nil }
        let ids = Set(burst.shots.map(\.id))
        if !check.inOtherAlbums.isDisjoint(with: ids) { return "a shot is also in another album, so this burst is left alone" }
        if !check.outsideTestAlbum.isDisjoint(with: ids) { return "not in the test album any more" }
        return nil
    }

    private var actionBar: some View {
        VStack(spacing: 6) {
            Button {
                confirming = true
            } label: {
                Text(approved.isEmpty ? "Pick bursts to clean" : (removeCount == 1 ? "Remove 1 Shot" : "Remove \(removeCount) Shots"))
            }
            .buttonStyle(.sticker)
            .disabled(approved.isEmpty || check == nil || model.isChanging)
            Text(check == nil ? (error == nil ? "Checking the test album…" : "Fix the problem above to continue.") : "Your picks stay. The other shots go to Recently Deleted.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .background(.bar)
    }

    // MARK: Actions

    /// Checks every shot once, so bursts that can't be touched are shown as such.
    private func runCheck() async {
        let all = Set(bursts.flatMap(\.shots).map(\.id))
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

    private func clean() async {
        let picks = approved
        guard !picks.isEmpty else { return }
        if let failure = await model.keepBurstPicks(picks) {
            error = failure
            await runCheck()
        } else {
            keepers = keepers.filter { id, _ in model.bursts.contains { $0.id == id } }
        }
    }
}

/// One burst: its shots side by side, with the keeper circled.
private struct BurstCard: View {
    let burst: Burst
    let keeper: MediaItem.ID?
    let blockedReason: String?
    let pick: (MediaItem.ID) -> Void
    let toggle: () -> Void

    private var isOn: Bool { keeper != nil && blockedReason == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button(action: toggle) {
                    HStack(spacing: 10) {
                        InkCheck(isOn: isOn, size: 24)
                            .opacity(blockedReason == nil ? 1 : 0.3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(burst.shots.count) shots")
                                .font(.subheadline.weight(.semibold))
                            if let blockedReason {
                                Text(blockedReason)
                                    .font(.hand(14))
                                    .foregroundStyle(Theme.tomato)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else if let first = burst.shots.first {
                                Text(first.creationDate.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(blockedReason != nil)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Burst of \(burst.shots.count) shots")
                .accessibilityValue(blockedReason ?? (isOn ? "Will be cleaned" : "Skipped"))
                .accessibilityAddTraits(.isButton)
                Spacer(minLength: 6)
                if isOn, let keeper {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("−\(ByteFormatter.string(burst.savedBytes(keeping: keeper), precision: .twoDecimals))")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(Theme.accent)
                        Text("\(burst.shots.count - 1) to remove")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(burst.shots) { shot in
                        shotButton(shot)
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 4)
            }
            .scrollIndicators(.hidden)
        }
        .card(padding: 14)
    }

    private func shotButton(_ shot: MediaItem) -> some View {
        let isKeeper = shot.id == keeper
        return Button {
            pick(shot.id)
        } label: {
            VStack(spacing: 6) {
                ItemThumbnail(id: shot.id, side: 72)
                    .opacity(isOn && !isKeeper ? 0.45 : 1)
                    .overlay {
                        if isOn && isKeeper {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Theme.accent, lineWidth: 3)
                                .padding(-5)
                        }
                    }
                Text(isOn ? (isKeeper ? "keep" : "remove") : (shot.traits.contains(.burstPick) ? "camera's pick" : " "))
                    .font(.hand(14))
                    .foregroundStyle(isOn ? (isKeeper ? Theme.accent : Theme.tomato) : Color.secondary)
            }
        }
        .buttonStyle(.plain)
        .disabled(blockedReason != nil)
        .accessibilityLabel(shot.filename)
        .accessibilityValue(isOn ? (isKeeper ? "Keep" : "Remove") : "Burst skipped")
        .accessibilityHint("Keeps this shot and removes the others in the burst")
    }
}
