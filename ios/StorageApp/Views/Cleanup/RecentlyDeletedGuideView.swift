import StorageCore
import SwiftUI
import UIKit

/// Shown right after a delete or a Live Photo conversion. iOS keeps removed
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

    enum Step: Int, CaseIterable {
        case done, why, openPhotos, findAlbum, select, confirm, measure

        var title: String {
            switch self {
            case .done: ""
            case .why: "The space isn't back yet"
            case .openPhotos: "Open Photos"
            case .findAlbum: "Find Recently Deleted"
            case .select: "Tap Select, pick, Delete"
            case .confirm: "Confirm on iOS"
            case .measure: "Your space, measured"
            }
        }

        var note: String {
            switch self {
            case .done, .measure: ""
            case .why: "iOS keeps deleted photos for 30 days in case you change your mind. Until you empty them, they still fill your iPhone."
            case .openPhotos: "Storage App can't empty Recently Deleted for you. Only you can, and it takes about ten seconds."
            case .findAlbum: "Scroll to the bottom, to Utilities. On iOS 17, it's in the Albums tab. Unlock it with Face ID or your passcode."
            case .select: "Pick only what Storage App just removed (shown below). Delete All works too, but only if nothing else in there matters to you."
            case .confirm: "Tap Delete From This iPhone. This is the step that gives the space back."
            }
        }

        var scene: [SceneMark] {
            switch self {
            case .done, .measure: []
            case .why: GuideScenes.waiting
            case .openPhotos: GuideScenes.openPhotos
            case .findAlbum: GuideScenes.findAlbum
            case .select: GuideScenes.select
            case .confirm: GuideScenes.confirm
            }
        }
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
            // Coming back from Photos: jump to the measurement.
            if phase == .active, step.rawValue >= Step.openPhotos.rawValue, step != .measure {
                forward = true
                withAnimation(.snappy) { step = .measure }
            }
        }
        .task(id: step) {
            if step == .measure { await model.measureReclaim() }
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
            StepDots(count: Step.allCases.count, current: step.rawValue)
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
        default: drawnPage
        }
    }

    private var drawnPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    StepNumber(number: step.rawValue, progress: progress)
                    Text(step.title)
                        .font(.display(28))
                        .tracking(-0.9)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }
                SketchCanvas(marks: step.scene, progress: progress)
                    .padding(.vertical, 18)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity)
                    .sticker(fill: Theme.surface, radius: 26, padding: 6)
                    .rotationEffect(.degrees(step.rawValue.isMultiple(of: 2) ? -0.6 : 0.7))
                Text(step.note)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
                if step == .select {
                    LookForThese(ids: guide.removedIDs)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityHint(step.note)
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 10) {
            switch step {
            case .openPhotos:
                Button {
                    if let url = URL(string: "photos-redirect://") { openURL(url) }
                } label: {
                    Label("Open Photos", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.sticker)
                Button("I'm in Photos, next") { go(+1) }
                    .buttonStyle(.soft)
            case .measure:
                Button(model.reclaim?.isDone == true ? "Done" : "Close for Now") { model.closeGuide() }
                    .buttonStyle(.sticker)
                if model.reclaim?.isDone != true {
                    Button("Show the Steps Again") {
                        forward = false
                        withAnimation(.snappy) { step = .openPhotos }
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
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private func go(_ delta: Int) {
        guard let next = Step(rawValue: step.rawValue + delta) else { return }
        forward = delta > 0
        withAnimation(.snappy(duration: 0.35)) { step = next }
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
                    .tracking(-1.1)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                VStack(alignment: .leading, spacing: 12) {
                    switch guide.kind {
                    case .deleted(let receipt):
                        deletedProof(receipt)
                    case .convertedLivePhotos(let results):
                        stillsProof(results)
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
        case .convertedLivePhotos: "same photos, lighter"
        }
    }

    private var title: String {
        switch guide.kind {
        case .deleted: "Moved \(guide.count == 1 ? "1 item" : "\(guide.count) items") to Recently Deleted"
        case .convertedLivePhotos: "Made \(guide.count == 1 ? "1 still" : "\(guide.count) stills")"
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
    private func stillsProof(_ results: [StillConversion]) -> some View {
        let all = results.allSatisfy(\.keptEverything)
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
            Text("VIDEO WAITING IN RECENTLY DELETED")
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
    @State private var isMeasuring = false

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
                            Text("checked \(latest.date.formatted(date: .omitted, time: .shortened))")
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
                    Text("Empty Recently Deleted, then come back here. Storage App measures again each time you return. iOS can take a minute to update free space.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    Task {
                        isMeasuring = true
                        await model.measureReclaim()
                        isMeasuring = false
                    }
                } label: {
                    Label(isMeasuring ? "Measuring…" : "Measure Again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.soft)
                .disabled(isMeasuring)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .sensoryFeedback(.success, trigger: done)
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

    var body: some View {
        if !ids.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("look for these")
                    .font(.hand(18))
                    .foregroundStyle(Theme.accent)
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(ids.prefix(30), id: \.self) { id in
                            ItemThumbnail(id: id, side: 54)
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
