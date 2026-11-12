import StorageCore
import SwiftUI

/// Step 5: keep the best shot of each burst in the library and move the
/// rest to Recently Deleted. The person picks the keeper; the camera's own
/// pick is chosen to start with.
///
/// It opens on All, where one tap cleans every burst. Select, in the top
/// bar, starts with nothing ticked so the person chooses which bursts.
/// Pressing and holding a shot opens the burst to swipe through.
struct BurstPicksView: View {
    @Environment(AppModel.self) private var model
    @State private var scope: PickScope = .all
    /// Burst ID → the shot the person picked to keep, where it isn't the suggested one.
    @State private var keepers: [String: MediaItem.ID] = [:]
    /// The bursts ticked in Select. All ignores it.
    @State private var chosen: Set<String> = []
    @State private var preview: MediaPreview?
    @State private var check: SafetyCheck?
    @State private var error: PhotoChangeError?
    @State private var confirming = false
    @State private var progress: CGFloat = 0

    private var bursts: [Burst] { model.bursts }

    /// The shot to keep: the person's pick while it's still in the burst, else the suggested one.
    private func keeper(of burst: Burst) -> MediaItem.ID {
        if let picked = keepers[burst.id], burst.shots.contains(where: { $0.id == picked }) { return picked }
        return burst.suggestedKeeper
    }
    /// Shots the safety check refused, such as ones that are gone since the scan.
    private var blocked: Set<MediaItem.ID> {
        guard let check else { return [] }
        return check.missing
    }
    /// What will happen if Remove is tapped now.
    private struct Totals {
        /// The bursts that will be cleaned: picked, and with no shot the check refused.
        var approved: [String: MediaItem.ID] = [:]
        var removeCount = 0
        var savedBytes: Int64 = 0
    }

    /// One pass over the bursts. Worked out once per redraw and handed to the
    /// parts that show it: a whole library can hold hundreds of bursts.
    private var totals: Totals {
        let blocked = blocked
        var totals = Totals()
        for burst in bursts {
            guard scope == .all || chosen.contains(burst.id) else { continue }
            let keeper = keeper(of: burst)
            if !blocked.isEmpty, burst.shots.contains(where: { blocked.contains($0.id) }) { continue }
            totals.approved[burst.id] = keeper
            totals.removeCount += burst.shots.count - 1
            totals.savedBytes += burst.savedBytes(keeping: keeper)
        }
        return totals
    }

    var body: some View {
        content(totals)
    }

    private func content(_ totals: Totals) -> some View {
        let removeCount = totals.removeCount
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(savedBytes: totals.savedBytes)
                SketchCanvas(marks: GuideScenes.burstPick, progress: progress)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity)
                    .sticker(radius: 26, padding: 8)
                    .rotationEffect(.degrees(0.6))
                Text(scope == .all
                     ? "Every burst is included. Tap the shot you want to keep in each one, or switch to Select at the top to choose which bursts. Press and hold a shot to swipe through the burst."
                     : "Tick the bursts to clean and tap the shot to keep in each. Press and hold a shot to swipe through the burst.")
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
        .scopePicker($scope, label: "Which bursts to clean", isShown: !bursts.isEmpty, isDisabled: model.isChanging)
        .safeAreaInset(edge: .bottom) { actionBar(totals) }
        .drawing($progress, duration: 3)
        .mediaPreview($preview)
        .overlay {
            if model.isChanging { WorkingOverlay(message: "Keeping your picks…") }
        }
        .confirmationDialog(
            "Keep \(totals.approved.count == 1 ? "1 shot" : "\(totals.approved.count) shots") and remove \(removeCount == 1 ? "1 other" : "\(removeCount) others")?",
            isPresented: $confirming,
            titleVisibility: .visible
        ) {
            Button(removeCount == 1 ? "Remove 1 Shot" : "Remove \(removeCount) Shots", role: .destructive) {
                Task { await clean(totals.approved) }
            }
        } message: {
            Text("Your picks stay in your library. The other shots go to Recently Deleted. You can recover them there for 30 days.")
        }
        .task(id: bursts.map(\.id)) {
            let left = Set(bursts.map(\.id))
            keepers = keepers.filter { left.contains($0.key) }
            chosen.formIntersection(left)
            await runCheck()
        }
    }

    // MARK: Sections

    private func header(savedBytes: Int64) -> some View {
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
                message: "Nothing in your library is a burst with more than one shot."
            )
        } else {
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(bursts) { burst in
                    let keeper = keeper(of: burst)
                    let pick: (MediaItem.ID) -> Void = { shot in
                        keepers[burst.id] = shot
                        chosen.insert(burst.id)
                    }
                    BurstCard(
                        burst: burst,
                        keeper: keeper,
                        showsCheck: scope == .select,
                        isIncluded: scope == .all || chosen.contains(burst.id),
                        blockedReason: blockedReason(burst),
                        pick: pick,
                        toggle: {
                            if chosen.contains(burst.id) { chosen.remove(burst.id) } else { chosen.insert(burst.id) }
                        },
                        hold: { shot in
                            preview = MediaPreview(
                                items: burst.shots, start: shot,
                                title: "Burst of \(burst.shots.count) shots", keeper: keeper, pick: pick
                            )
                        }
                    )
                }
            }
        }
    }

    private func blockedReason(_ burst: Burst) -> String? {
        guard let check, !check.missing.isEmpty else { return nil }
        if burst.shots.contains(where: { check.missing.contains($0.id) }) { return "not in your library any more" }
        return nil
    }

    private func actionBar(_ totals: Totals) -> some View {
        let approved = totals.approved
        let removeCount = totals.removeCount
        return VStack(spacing: 6) {
            Button {
                confirming = true
            } label: {
                Text(approved.isEmpty ? "Pick bursts to clean" : (removeCount == 1 ? "Remove 1 Shot" : "Remove \(removeCount) Shots"))
            }
            .buttonStyle(.sticker)
            .disabled(approved.isEmpty || check == nil || model.isChanging)
            Text(check == nil ? (error == nil ? "Checking your library…" : "Fix the problem above to continue.") : "Your picks stay. The other shots go to Recently Deleted.")
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

    private func clean(_ picks: [String: MediaItem.ID]) async {
        guard !picks.isEmpty else { return }
        if let failure = await model.keepBurstPicks(picks) {
            await runCheck()
            // After the check: a successful re-check used to clear this message.
            error = failure
        }
    }
}

/// One burst: its shots side by side, with the keeper circled.
private struct BurstCard: View {
    let burst: Burst
    let keeper: MediaItem.ID
    /// Select shows a tick on each burst; All includes every one.
    let showsCheck: Bool
    let isIncluded: Bool
    let blockedReason: String?
    let pick: (MediaItem.ID) -> Void
    let toggle: () -> Void
    /// A shot was pressed and held.
    let hold: (MediaItem.ID) -> Void

    private var isOn: Bool { isIncluded && blockedReason == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button(action: toggle) {
                    HStack(spacing: 10) {
                        if showsCheck {
                            InkCheck(isOn: isOn, size: 24)
                                .opacity(blockedReason == nil ? 1 : 0.3)
                        }
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
                // All includes every burst, so there's nothing to tick.
                .allowsHitTesting(showsCheck)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Burst of \(burst.shots.count) shots")
                .accessibilityValue(blockedReason ?? (isOn ? "Will be cleaned" : "Skipped"))
                .accessibilityAddTraits(.isButton)
                Spacer(minLength: 6)
                if isOn {
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
                // Lazy: a burst can hold a hundred shots, and each one loads a thumbnail.
                LazyHStack(spacing: 10) {
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
        return VStack(spacing: 6) {
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
        .accessibilityElement(children: .ignore)
        .tapAndHold(isEnabled: blockedReason == nil) {
            pick(shot.id)
        } hold: {
            hold(shot.id)
        }
        .accessibilityLabel(shot.filename)
        .accessibilityValue(isOn ? (isKeeper ? "Keep" : "Remove") : "Burst skipped")
        .accessibilityHint("Keeps this shot and removes the others in the burst")
    }
}
