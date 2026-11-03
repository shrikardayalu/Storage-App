import StorageCore
import SwiftUI
import UIKit

/// Shown right after a delete, a Live Photo conversion, a burst cleanup or a
/// smaller video. iOS keeps removed
/// photos in Recently Deleted for 30 days, so the space only comes back once
/// the person empties it. Only they can do that, so this walks them through it
/// with drawings that ink themselves in, then measures the space that came back.
struct RecentlyDeletedGuideView: View {
    let guide: CleanupGuide

    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var step: Step = .done
    @State private var forward = true
    @State private var progress: CGFloat = 0
    /// Off once the person knows the flow: a one-page summary replaces the steps.
    @AppStorage(Self.showStepsKey) private var showSteps = true
    /// Shows the full steps this time only, while they stay off.
    @State private var seeFullSteps = false

    /// Also toggled in Settings.
    static let showStepsKey = "guide.showSteps"

    /// After a swap, a new version stays in the library and what's in Recently
    /// Deleted is the old one, so the guide says which is which.
    enum Swap {
        /// Nothing was swapped: what's in Recently Deleted is simply gone.
        case none
        /// Live Photos became stills; the old Live versions are in Recently Deleted.
        case stills
        /// A video was replaced by a smaller copy; the original is in Recently Deleted.
        case video
    }

    enum Step: Int {
        case done, why, openPhotos, findAlbum, select, confirm, measure
        /// All the steps on one page, for people who turned the steps off.
        case summary

        /// Steps where the person is about to go to Photos, or already there.
        var isInPhotos: Bool {
            switch self {
            case .openPhotos, .findAlbum, .select, .confirm, .summary: true
            case .done, .why, .measure: false
            }
        }

        func title(swap: Swap) -> String {
            switch self {
            case .done, .summary: ""
            case .why:
                switch swap {
                case .none: "The space isn't back yet"
                case .stills: "Your stills are safe"
                case .video: "Your smaller video is safe"
                }
            case .openPhotos: "Open Photos"
            case .findAlbum: "Find Recently Deleted"
            case .select:
                switch swap {
                case .none: "Tap Select, pick, Delete"
                case .stills: "Delete only the Live versions"
                case .video: "Delete only the original"
                }
            case .confirm: "Confirm on iOS"
            case .measure: "Your space, measured"
            }
        }

        func note(swap: Swap) -> String {
            switch self {
            case .done, .measure, .summary: ""
            case .why:
                switch swap {
                case .none: "iOS keeps deleted photos for 30 days in case you change your mind. Until you empty them, they still fill your iPhone."
                case .stills: "Each still is already in your library and the test album, right where the Live Photo was. What went to Recently Deleted is only the old Live version: the same photo plus its 3-second video. iOS keeps it for 30 days, so it still takes space until you empty it."
                case .video: "The smaller copy is already in your library and the test album, with the same date and place. What went to Recently Deleted is the original, full-size video. iOS keeps it for 30 days, so it still takes space until you empty it."
                }
            case .openPhotos: "Storage App can't empty Recently Deleted for you. Only you can, and it takes about ten seconds."
            case .findAlbum: "Scroll to the bottom, to Utilities. On iOS 17, it's in the Albums tab. Unlock it with Face ID or your passcode."
            case .select:
                switch swap {
                case .none: "Pick only what Storage App just removed (shown below). Delete All works too, but only if nothing else in there matters to you."
                case .stills: "The photos from Storage App in here are the old Live versions (shown below). They look like your stills because they're the same photo, but your stills never go in Recently Deleted. Deleting these only removes the extra video."
                case .video: "The video from Storage App in here is the original, full-size one (shown below). It looks like your smaller copy because it's the same video, but your copy never goes in Recently Deleted."
                }
            case .confirm:
                switch swap {
                case .none: "Tap Delete From This iPhone. This is the step that gives the space back."
                case .stills: "Tap Delete From This iPhone. This erases only the old Live versions. Your stills stay in your library."
                case .video: "Tap Delete From This iPhone. This erases only the original. Your smaller video stays in your library."
                }
            }
        }

        func scene(swap: Swap) -> [SceneMark] {
            switch self {
            case .done, .measure, .summary: []
            case .why: swap == .stills ? GuideScenes.stillsKept : GuideScenes.waiting
            case .openPhotos: GuideScenes.openPhotos
            case .findAlbum: GuideScenes.findAlbum
            case .select: GuideScenes.select
            case .confirm: GuideScenes.confirm
            }
        }
    }

    private var swap: Swap {
        switch guide.kind {
        case .convertedLivePhotos: .stills
        case .shrunkVideo: .video
        case .deleted, .keptBurstPicks: .none
        }
    }

    /// The pages in order: every step, or the summary once steps are off.
    private var steps: [Step] {
        showSteps || seeFullSteps
            ? [.done, .why, .openPhotos, .findAlbum, .select, .confirm, .measure]
            : [.done, .summary, .measure]
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ZStack {
                page
                    .id(step)
                    .transition(.asymmetric(
                        insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                        removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)
                    ))
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .gesture(DragGesture(minimumDistance: 30).onEnded { value in
                if value.translation.width < -60 { go(+1) }
                if value.translation.width > 60 { go(-1) }
            })
            controls
        }
        .background(PaperBackground())
        .drawing($progress, duration: step == .done ? 2.2 : 3.4, key: step)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            // Coming back from Photos: jump to the measurement, or measure again.
            if step == .measure {
                Task { await model.checkReclaim() }
            } else if step.isInPhotos {
                forward = true
                withAnimation(.snappy) { step = .measure }
            }
        }
        .task(id: step) {
            if step == .measure { await model.checkReclaim() }
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                model.closeGuide()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.bold))
                    .frame(width: 40, height: 40)
                    .background(Theme.surface, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.ink, lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close guide")
            Spacer()
            StepDots(count: steps.count, current: steps.firstIndex(of: step) ?? 0)
            Spacer()
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: Pages

    @ViewBuilder
    private var page: some View {
        switch step {
        case .done: DonePage(guide: guide, progress: progress)
        case .measure: MeasurePage(guide: guide, progress: progress)
        case .summary:
            SummaryPage(guide: guide, swap: swap, progress: progress)
        default: drawnPage
        }
    }

    private var drawnPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    StepNumber(number: step.rawValue, progress: progress)
                    Text(step.title(swap: swap))
                        .font(.display(28))
                        .boiling()
                        .tracking(-0.9)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }
                if swap != .none {
                    SwapSafeNote(swap: swap)
                }
                SketchCanvas(marks: step.scene(swap: swap), progress: progress)
                    .padding(.vertical, 18)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity)
                    .sticker(fill: Theme.surface, radius: 26, padding: 6)
                    .rotationEffect(.degrees(step.rawValue.isMultiple(of: 2) ? -0.6 : 0.7))
                Text(step.note(swap: swap))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
                if step == .select {
                    LookForThese(ids: guide.removedIDs, stills: swap == .stills)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityHint(step.note(swap: swap))
    }

    /// Small links under the buttons, pinned so they never scroll out of view.
    @ViewBuilder
    private var stepLinks: some View {
        if step == .summary {
            HStack(spacing: 20) {
                Button("See the Full Steps") { showFullSteps(keepOn: false) }
                Button("Turn Steps Back On") { showFullSteps(keepOn: true) }
            }
            .modifier(GuideLinkStyle())
        } else if step.isInPhotos || step == .why, showSteps {
            // Turns the steps off for good and switches to the one-page summary.
            Button("Skip these steps from now on") {
                showSteps = false
                seeFullSteps = false
                forward = true
                withAnimation(.snappy) { step = .summary }
            }
            .modifier(GuideLinkStyle())
            .accessibilityHint("Shows a one-page summary instead. You can turn the steps back on in Settings.")
        }
    }

    /// From the summary: the full steps, this time only or from now on.
    private func showFullSteps(keepOn: Bool) {
        if keepOn { showSteps = true } else { seeFullSteps = true }
        forward = true
        withAnimation(.snappy) { step = .why }
    }

    private func openPhotos() {
        if let url = URL(string: "photos-redirect://") { openURL(url) }
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 10) {
            switch step {
            case .openPhotos:
                Button(action: openPhotos) {
                    Label("Open Photos", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.sticker)
                Button("I'm in Photos, next") { go(+1) }
                    .buttonStyle(.soft)
            case .summary:
                Button(action: openPhotos) {
                    Label("Open Photos", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.sticker)
                Button("I Emptied It, Measure") { go(+1) }
                    .buttonStyle(.soft)
            case .measure:
                Button(model.reclaim?.isDone == true ? "Done" : "Close for Now") { model.closeGuide() }
                    .buttonStyle(.sticker)
                if model.reclaim?.isDone != true {
                    Button(steps.contains(.summary) ? "Show the Summary Again" : "Show the Steps Again") {
                        forward = false
                        withAnimation(.snappy) { step = steps.contains(.summary) ? .summary : .openPhotos }
                    }
                    .buttonStyle(.soft)
                }
            default:
                Button(step == .done ? "Get the Space Back" : "Next") { go(+1) }
                    .buttonStyle(.sticker)
                if step != .done {
                    Button("Back") { go(-1) }
                        .buttonStyle(.soft)
                }
            }
            stepLinks
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private func go(_ delta: Int) {
        guard let index = steps.firstIndex(of: step), steps.indices.contains(index + delta) else { return }
        forward = delta > 0
        withAnimation(.snappy(duration: 0.35)) { step = steps[index + delta] }
    }
}

// MARK: - Done page

/// What just happened, with proof that only the approved items changed.
private struct DonePage: View {
    let guide: CleanupGuide
    let progress: CGFloat

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(eyebrow)
                    .font(.hand(21))
                    .foregroundStyle(Theme.accent)
                    .handwritten(progress, start: 0, length: 0.2)
                Text(title)
                    .font(.display(34))
                    .boiling()
                    .tracking(-1.1)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                VStack(alignment: .leading, spacing: 12) {
                    switch guide.kind {
                    case .deleted(let receipt):
                        deletedProof(receipt)
                    case .convertedLivePhotos(let results):
                        stillsProof(results)
                    case .keptBurstPicks(let receipt):
                        burstProof(receipt)
                    case .shrunkVideo(let result):
                        videoProof(result)
                    }
                }
                .onReceipt()
                .overlay(alignment: .bottomTrailing) {
                    RubberStamp(top: "only touched", main: "what you OK'd")
                        .stamped(progress, at: 0.78)
                        .offset(x: 4, y: 20)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
    }

    private var eyebrow: String {
        switch guide.kind {
        case .deleted: "done, and double-checked"
        case .convertedLivePhotos: "same photos, minus the video"
        case .keptBurstPicks: "best shots kept"
        case .shrunkVideo: "same memory, smaller file"
        }
    }

    private var title: String {
        switch guide.kind {
        case .deleted: "Moved \(guide.count == 1 ? "1 item" : "\(guide.count) items") to Recently Deleted"
        case .convertedLivePhotos: "Made \(guide.count == 1 ? "1 still" : "\(guide.count) stills")"
        case .keptBurstPicks(let receipt):
            "Kept \(receipt.keepers.count == 1 ? "1 shot" : "\(receipt.keepers.count) shots"), moved \(guide.count) to Recently Deleted"
        case .shrunkVideo(let result): result.wasTrimmed ? "Trimmed and shrank your video" : "Shrank your video"
        }
    }

    @ViewBuilder
    private func deletedProof(_ receipt: DeletionReceipt) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Test album")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text("\(receipt.albumCountBefore) → \(receipt.albumCountAfter) items")
                .font(.metric(.title3))
                .monospacedDigit()
        }
        DashedRule()
        SafetyLine(done: receipt.onlyApprovedRemoved, text: "Exactly the \(receipt.deleted.count) you approved left the album", progress: progress, start: 0.3)
        SafetyLine(done: receipt.onlyApprovedRemoved, text: "Every other item is still there", progress: progress, start: 0.42)
        SafetyLine(done: true, text: "Nothing outside \u{201C}\(TestMode.albumName)\u{201D} was touched", progress: progress, start: 0.54)
        DashedRule()
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text("WAITING IN RECENTLY DELETED")
                    .font(.caption2.weight(.bold))
                    .tracking(1.4)
                    .foregroundStyle(.secondary)
                SizeText(bytes: receipt.deletedBytes, style: .largeTitle, unitStyle: .title3, precision: .twoDecimals)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func burstProof(_ receipt: BurstReceipt) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Test album")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text("\(receipt.albumCountBefore) → \(receipt.albumCountAfter) items")
                .font(.metric(.title3))
                .monospacedDigit()
        }
        DashedRule()
        SafetyLine(
            done: receipt.keptPick.count == receipt.keepers.count,
            text: receipt.keepers.count == 1 ? "The burst has only your pick left" : "Each of the \(receipt.keepers.count) bursts has only your pick left",
            progress: progress, start: 0.3
        )
        SafetyLine(done: receipt.onlyApprovedRemoved, text: "Exactly the other \(receipt.removed.count) shots left the album", progress: progress, start: 0.42)
        SafetyLine(done: true, text: "Nothing outside \u{201C}\(TestMode.albumName)\u{201D} was touched", progress: progress, start: 0.54)
        DashedRule()
        VStack(alignment: .leading, spacing: 2) {
            Text("WAITING IN RECENTLY DELETED")
                .font(.caption2.weight(.bold))
                .tracking(1.4)
                .foregroundStyle(.secondary)
            SizeText(bytes: receipt.removedBytes, style: .largeTitle, unitStyle: .title3, precision: .twoDecimals)
        }
    }

    @ViewBuilder
    private func videoProof(_ result: VideoReplacement) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Video")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text("\(ByteFormatter.string(result.originalBytes, precision: .twoDecimals)) → \(ByteFormatter.string(result.newBytes, precision: .twoDecimals))")
                .font(.metric(.title3))
                .monospacedDigit()
        }
        DashedRule()
        SafetyLine(done: result.isSmaller, text: "Smaller, by \(ByteFormatter.string(max(result.savedBytes, 0), precision: .twoDecimals))", progress: progress, start: 0.26)
        SafetyLine(
            done: result.rightLength,
            text: result.wasTrimmed
                ? "Trimmed to \(VideoTime.string(result.newDuration)) of \(VideoTime.string(result.originalDuration))"
                : "Full length, \(VideoTime.string(result.newDuration))",
            progress: progress, start: 0.34
        )
        SafetyLine(done: result.keptDate, text: "Date kept", progress: progress, start: 0.42)
        SafetyLine(done: result.keptLocation, text: "Location kept", progress: progress, start: 0.5)
        SafetyLine(done: result.keptFavorite, text: "Favorite kept", progress: progress, start: 0.58)
        SafetyLine(done: result.keptAlbum && result.originalGone, text: "Swapped in \u{201C}\(TestMode.albumName)\u{201D}", progress: progress, start: 0.66)
        if !result.keptEverything {
            Text("Something didn't match. The original is in Recently Deleted, so you can recover it there instead of emptying it.")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.tomato)
                .fixedSize(horizontal: false, vertical: true)
        }
        DashedRule()
        VStack(alignment: .leading, spacing: 2) {
            Text("ORIGINAL IN RECENTLY DELETED")
                .font(.caption2.weight(.bold))
                .tracking(1.4)
                .foregroundStyle(.secondary)
            SizeText(bytes: result.originalBytes, style: .largeTitle, unitStyle: .title3, precision: .twoDecimals)
        }
    }

    @ViewBuilder
    private func stillsProof(_ results: [StillConversion]) -> some View {
        let all = results.allSatisfy(\.keptEverything)
        if let first = results.first {
            KeptVersusGoing(conversion: first, more: results.count - 1)
            DashedRule()
        }
        SafetyLine(done: results.allSatisfy(\.isSameStill), text: "Same photo, same size, no video", progress: progress, start: 0.26)
        SafetyLine(done: results.allSatisfy(\.keptDate), text: "Date kept", progress: progress, start: 0.34)
        SafetyLine(done: results.allSatisfy(\.keptLocation), text: "Location kept", progress: progress, start: 0.42)
        SafetyLine(done: results.allSatisfy(\.keptFavorite), text: "Favorites kept", progress: progress, start: 0.5)
        SafetyLine(done: results.allSatisfy(\.keptAlbum), text: "Still in \u{201C}\(TestMode.albumName)\u{201D}", progress: progress, start: 0.58)
        if !all {
            Text("\(results.filter { !$0.keptEverything }.count) didn't match exactly. The originals are in Recently Deleted, so you can recover them there instead of emptying it.")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.tomato)
                .fixedSize(horizontal: false, vertical: true)
        }
        DashedRule()
        VStack(alignment: .leading, spacing: 2) {
            Text("OLD LIVE VERSIONS IN RECENTLY DELETED")
                .font(.caption2.weight(.bold))
                .tracking(1.4)
                .foregroundStyle(.secondary)
            SizeText(bytes: guide.expectedBytes, style: .largeTitle, unitStyle: .title3, precision: .twoDecimals)
        }
    }
}

// MARK: - Measure page

/// Free space now versus right before the cleanup, re-read each time the
/// person comes back to the app.
private struct MeasurePage: View {
    let guide: CleanupGuide
    let progress: CGFloat
    @Environment(AppModel.self) private var model

    private static let design = CGSize(width: 300, height: 90)

    var body: some View {
        let reclaim = model.reclaim
        let done = reclaim?.isDone == true
        let reclaimed = reclaim?.reclaimedBytes ?? 0
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(done ? "there it is" : "come back after emptying it")
                    .font(.hand(21))
                    .foregroundStyle(Theme.accent)
                    .handwritten(progress, start: 0, length: 0.2)
                Text(done ? "You got your space back" : "Not back yet")
                    .font(.display(34))
                    .boiling()
                    .tracking(-1.1)
                    .accessibilityAddTraits(.isHeader)

                VStack(alignment: .leading, spacing: 10) {
                    Text("FREE SPACE BACK")
                        .font(.caption2.weight(.bold))
                        .tracking(1.8)
                        .foregroundStyle(.secondary)
                    CountingSize(bytes: reclaimed)
                    DrawnStroke(path: Sketch.scribble(width: 200, at: CGPoint(x: 6, y: 10), seed: 300), design: CGSize(width: 220, height: 20), progress: progress, start: 0.3, length: 0.3)
                        .stroke(done ? Theme.mint : Theme.ink.opacity(0.2), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 220, height: 20)

                    // A drawn bar that fills toward what the cleanup should give back.
                    ZStack(alignment: .leading) {
                        GeometryReader { proxy in
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Theme.mint)
                                .frame(width: max(0, (proxy.size.width - 8) * CGFloat(reclaim?.fraction ?? 0)))
                                .padding(4)
                                .offset(x: -2, y: 2)
                                .animation(.spring(response: 0.9, dampingFraction: 0.75), value: reclaim?.fraction)
                        }
                        DrawnStroke(path: Sketch.box(CGRect(x: 4, y: 4, width: 292, height: 40), radius: 12, seed: 301), design: CGSize(width: 300, height: 48), progress: progress, start: 0.1, length: 0.3)
                            .stroke(Theme.ink, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                    }
                    .frame(height: 48)
                    .accessibilityHidden(true)

                    HStack {
                        Text("of \(ByteFormatter.string(guide.expectedBytes, precision: .twoDecimals)) waiting")
                        Spacer()
                        if let latest = reclaim?.latest {
                            Text("checked \(latest.date.formatted(date: .omitted, time: .standard))")
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .sticker(radius: 24, padding: 0)
                .overlay(alignment: .topTrailing) {
                    if done {
                        RubberStamp(top: "measured", main: "space back")
                            .stamped(progress, at: 0.55)
                            .offset(x: 8, y: -18)
                    }
                }

                if !done {
                    checkStatus
                        .animation(.snappy, value: model.isCheckingReclaim)
                }

                Button {
                    Task { await model.checkReclaim() }
                } label: {
                    HStack(spacing: 8) {
                        if model.isCheckingReclaim {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text(model.isCheckingReclaim ? "Checking Free Space…" : "Measure Again")
                    }
                }
                .buttonStyle(.soft)
                .disabled(model.isCheckingReclaim)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .sensoryFeedback(.success, trigger: done)
    }

    /// What the last check found, so a tap never looks like nothing happened.
    @ViewBuilder
    private var checkStatus: some View {
        let check = model.lastReclaimCheck
        VStack(alignment: .leading, spacing: 6) {
            if model.isCheckingReclaim {
                Text("Reading free space for a few seconds, since iOS can be slow to count space from Recently Deleted.")
            } else if let check {
                Text(check.gainedBytes > 0
                     ? "Checked at \(check.date.formatted(date: .omitted, time: .standard)): \(ByteFormatter.string(check.gainedBytes, precision: .twoDecimals)) more came back. Still counting."
                     : "Checked at \(check.date.formatted(date: .omitted, time: .standard)): no change yet.")
                    .fontWeight(.semibold)
                    .foregroundStyle(check.gainedBytes > 0 ? Theme.ink : Theme.tomato)
                Text("Open Recently Deleted in Photos. If the items are still there, they aren't erased yet: tap Select, pick them, then Delete From This iPhone. If it's empty, give iOS a minute and measure again.")
            } else {
                Text("Empty Recently Deleted, then come back here. Storage App measures again each time you return. iOS can take a minute to update free space.")
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// The guide's small text links: tinted, with a tap area big enough to hit.
private struct GuideLinkStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.accent)
            .buttonStyle(.plain)
            .frame(minHeight: 32)
            .contentShape(Rectangle())
    }
}

// MARK: - Summary page

/// All the steps on one page, for people who turned the steps off. The way
/// back to the full steps is in the guide's controls.
private struct SummaryPage: View {
    let guide: CleanupGuide
    let swap: RecentlyDeletedGuideView.Swap
    let progress: CGFloat

    private var lines: [String] {
        [
            "Open Photos.",
            "Scroll down to Utilities (the Albums tab on iOS 17), tap Recently Deleted and unlock it.",
            selectLine,
            "Tap Delete From This iPhone.",
        ]
    }

    private var selectLine: String {
        switch swap {
        case .none: "Tap Select, pick what Storage App just removed, then Delete."
        case .stills: "Tap Select, pick only the old Live versions, then Delete."
        case .video: "Tap Select, pick only the original video, then Delete."
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("the quick version")
                    .font(.hand(21))
                    .foregroundStyle(Theme.accent)
                    .handwritten(progress, start: 0, length: 0.2)
                Text("Empty Recently Deleted")
                    .font(.display(34))
                    .boiling()
                    .tracking(-1.1)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if swap != .none {
                    SwapSafeNote(swap: swap)
                }

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        HStack(alignment: .center, spacing: 12) {
                            StepNumber(number: index + 1, progress: progress)
                            Text(line)
                                .font(.body.weight(.medium))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Step \(index + 1): \(line)")
                    }
                    DashedRule()
                    HStack(alignment: .firstTextBaseline) {
                        Text("Waiting in Recently Deleted")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(ByteFormatter.string(guide.expectedBytes, precision: .twoDecimals))
                            .font(.metric(.title3))
                            .monospacedDigit()
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .sticker(radius: 24, padding: 0)

                LookForThese(ids: guide.removedIDs, stills: swap == .stills)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
    }
}

/// A size that counts up to its value whenever it changes.
private struct CountingSize: View {
    var bytes: Int64
    @State private var shown: Double = 0

    var body: some View {
        Color.clear
            .frame(height: 0)
            .modifier(CountingText(value: shown))
            .onAppear { withAnimation(.easeOut(duration: 1.2)) { shown = Double(bytes) } }
            .onChange(of: bytes) { _, new in withAnimation(.easeOut(duration: 1.2)) { shown = Double(new) } }
            .accessibilityLabel(ByteFormatter.accessibilityString(bytes, precision: .twoDecimals))
    }
}

private struct CountingText: ViewModifier, Animatable {
    var value: Double

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    func body(content: Content) -> some View {
        SizeText(bytes: Int64(value), style: .largeTitle, unitStyle: .title2, precision: .twoDecimals)
    }
}

// MARK: - Bits

/// A step number inside a hand-drawn circle.
private struct StepNumber: View {
    let number: Int
    let progress: CGFloat

    var body: some View {
        ZStack {
            DrawnStroke(path: Sketch.loop(around: CGRect(x: 6, y: 6, width: 32, height: 32), turns: 1.1, seed: UInt64(number) + 400), design: CGSize(width: 44, height: 44), progress: progress, start: 0, length: 0.18)
                .stroke(Theme.ink, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            Text("\(number)")
                .font(.hand(24))
                .handwritten(progress, start: 0.08, length: 0.1)
        }
        .frame(width: 44, height: 44)
        .accessibilityHidden(true)
    }
}

/// Small wobbly dots for where you are in the guide.
private struct StepDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index <= current ? Theme.mint : Theme.well)
                    .overlay(Capsule().strokeBorder(Theme.ink, lineWidth: index == current ? 1.5 : 0))
                    .frame(width: index == current ? 22 : 8, height: 8)
            }
        }
        .animation(.snappy, value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current + 1) of \(count)")
    }
}

/// Thumbnails of what was removed, from the cache, so the person knows what to pick.
private struct LookForThese: View {
    let ids: [MediaItem.ID]
    var stills = false

    var body: some View {
        if !ids.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(stills ? "look for these, with the LIVE badge" : "look for these")
                    .font(.hand(18))
                    .foregroundStyle(Theme.accent)
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(ids.prefix(30), id: \.self) { id in
                            ItemThumbnail(id: id, side: 54)
                                .overlay(alignment: .topLeading) { if stills { LiveBadge().padding(3) } }
                                .rotationEffect(.degrees(Double(abs(id.hashValue % 5)) - 2))
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.hidden)
            }
            .padding(.top, 4)
        }
    }
}

/// A reminder on every step after a swap: the new version is not in Recently Deleted.
private struct SwapSafeNote: View {
    let swap: RecentlyDeletedGuideView.Swap

    var body: some View {
        HStack(spacing: 10) {
            InkCheck(isOn: true, size: 24)
            Text(swap == .video
                 ? "Your smaller video stays in your library. Only the original is in Recently Deleted."
                 : "Your stills stay in your library. Only the old Live versions are in Recently Deleted.")
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .sticker(fill: Theme.mintSoft, radius: 16, padding: 12)
        .accessibilityElement(children: .combine)
    }
}

/// A small "LIVE" tag like the one Photos shows on Live Photos.
struct LiveBadge: View {
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "livephoto")
            Text("LIVE")
        }
        .font(.system(size: 8, weight: .heavy))
        .foregroundStyle(Color(hex: 0x1A1A17))
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(.white.opacity(0.85), in: Capsule())
        .accessibilityHidden(true)
    }
}

/// Side by side: the still that stays, and the Live version that went to Recently Deleted.
private struct KeptVersusGoing: View {
    let conversion: StillConversion
    let more: Int

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            column(
                id: conversion.stillID, live: false, color: Theme.accent,
                heading: "KEPT", detail: "Your still, in your library and the test album"
            )
            Image(systemName: "arrow.left.arrow.right")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.tertiary)
                .padding(.top, 40)
            column(
                id: conversion.originalID, live: true, color: Theme.tomato,
                heading: "IN RECENTLY DELETED", detail: "The old Live version: same photo plus its video"
            )
        }
        if more > 0 {
            Text("Same for the other \(more == 1 ? "1 photo" : "\(more) photos").")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func column(id: MediaItem.ID, live: Bool, color: Color, heading: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ItemThumbnail(id: id, side: 96)
                .overlay(alignment: .topLeading) { if live { LiveBadge().padding(4) } }
            Text(heading)
                .font(.caption2.weight(.heavy))
                .tracking(1.2)
                .foregroundStyle(color)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
