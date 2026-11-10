import StorageCore
import SwiftUI
import UIKit

/// First run: two screens that say "we get it", a live scan that shows where
/// the space went, then "which ones do you want to try?". No paywall: see
/// `OnboardingStep` for why. Every number shown is the person's own: real free space
/// on the first two screens, a real scan, real estimates on the picks.
///
/// One drawing, `HeroPhone`, stays on screen the whole way and moves between
/// steps, so the flow reads as one story instead of a stack of slides: the
/// phone fills, the alerts fall out of it, it prints the scan, and it drains
/// as the picks add up. Only the words change.
struct OnboardingFlow: View {
    var startAt: OnboardingStep = .hook
    /// Fixed suggestions for CI screenshots, which have no library to scan.
    var sampleSuggestions: [Suggestion]?
    let onFinish: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(PurchaseStore.self) private var purchases
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: OnboardingStep = .hook
    @State private var answers = OnboardingAnswers()
    @State private var suggestions: [Suggestion] = []

    // The hero phone's story so far.
    @State private var drawProgress: CGFloat = 0
    @State private var filled = false
    /// The photos spilling out of a nearly full phone have been drawn on.
    @State private var spilled = false
    /// The padlock has been drawn on for the scan.
    @State private var locked = false
    @State private var stamped = false
    @State private var drained = false
    @State private var stampTick = 0

    var body: some View {
        GeometryReader { proxy in
            let hero = heroFrame(for: step, in: proxy.size)
            ZStack(alignment: .top) {
                PaperBackground()
                page(top: step == .paywall ? 0 : hero.maxY + 14)
                    .id(step)
                    .transition(.onboardingPage)
                HeroPhone(
                    drawProgress: drawProgress,
                    level: heroLevel,
                    spill: step == .hook && spilled && usedFraction >= 0.7 ? 1 : 0,
                    lock: step == .scan && locked ? 1 : 0,
                    stamped: stamped && (step == .hook || step == .pain)
                )
                .frame(width: hero.width, height: hero.height)
                .rotationEffect(.degrees(tilt(for: step)))
                .position(x: hero.midX, y: hero.midY)
                .opacity(step == .paywall ? 0 : 1)
                .allowsHitTesting(false)
                if step != .paywall {
                    TopBar(step: step, onBack: back)
                }
            }
        }
        .animation(.spring(response: 0.62, dampingFraction: 0.8), value: step)
        .sensoryFeedback(.impact(weight: .light), trigger: step)
        .sensoryFeedback(.impact(weight: .heavy), trigger: stampTick)
        .onAppear(perform: begin)
        .onChange(of: step) { _, new in
            if new == .picks { drain() }
            drawLock(new == .scan)
        }
    }

    @ViewBuilder
    private func page(top: CGFloat) -> some View {
        switch step {
        case .hook:
            HookPage(top: top, onNext: advance)
        case .pain:
            PainPage(top: top, onNext: advance)
        case .scan:
            ScanPage(top: top) { found in
                suggestions = found ?? []
                if suggestions.isEmpty {
                    // No access, an empty album, or nothing to suggest: straight to Home.
                    finish()
                } else {
                    advance()
                }
            }
        case .picks:
            PicksPage(top: top, suggestions: suggestions, picks: $answers.picks, onNext: advance)
        case .paywall:
            PaywallFlow(context: PaywallContext(proBytes: model.proSaving), onDone: finish)
        }
    }

    // MARK: The hero's place and state on each step

    /// Where the phone sits: big on the hook, then tucked above each step's words.
    private func heroFrame(for step: OnboardingStep, in size: CGSize) -> CGRect {
        let share: CGFloat
        switch step {
        case .hook: share = 0.42
        case .pain: share = 0.19
        case .scan: share = 0.12
        case .picks: share = 0.1
        case .paywall: share = 0.1
        }
        let height = size.height * share
        let width = height * HeroPhone.design.width / HeroPhone.design.height
        let top: CGFloat = step == .hook ? 58 : 48
        return CGRect(x: (size.width - width) / 2, y: top, width: width, height: height)
    }

    private func tilt(for step: OnboardingStep) -> Double {
        switch step {
        case .pain: -5
        case .picks: 4
        default: 0
        }
    }

    private var usedFraction: Double { model.deviceStorage?.usedFraction ?? 0.9 }

    /// Empty, then the phone's real fill, then what's left if every suggestion were done.
    private var heroLevel: CGFloat {
        guard filled else { return 0 }
        guard drained, let total = model.deviceStorage?.totalBytes, total > 0 else { return CGFloat(usedFraction) }
        return CGFloat(max(0.04, usedFraction - Double(suggestions.totalBytes) / Double(total)))
    }

    /// The hook draws the phone in, fills it, draws the photos spilling out of
    /// it, then stamps it. Later steps (screenshot routes) start with all of
    /// that already drawn.
    private func begin() {
        step = startAt
        if let sampleSuggestions { suggestions = sampleSuggestions }
        guard startAt == .hook, !reduceMotion else {
            drawProgress = 1
            filled = true
            spilled = true
            stamped = usedFraction >= 0.8
            if startAt == .picks { drain() }
            return
        }
        Task {
            try? await Task.sleep(for: .milliseconds(80))
            withAnimation(.easeInOut(duration: 1.1)) { drawProgress = 1 }
            try? await Task.sleep(for: .milliseconds(750))
            withAnimation(.easeInOut(duration: 1.3)) { filled = true }
            // The photos start spilling over as the tank nears the top. Linear,
            // because each stroke already speeds up and slows down on its own.
            try? await Task.sleep(for: .milliseconds(700))
            withAnimation(.linear(duration: 1.1)) { spilled = true }
            guard usedFraction >= 0.8 else { return }
            try? await Task.sleep(for: .milliseconds(700))
            withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { stamped = true }
            stampTick += 1
        }
    }

    /// The padlock is drawn on once the phone has settled above the scan, and
    /// rubbed out when the scan is over.
    private func drawLock(_ on: Bool) {
        guard on else {
            withAnimation(.easeOut(duration: 0.25)) { locked = false }
            return
        }
        guard !reduceMotion else {
            locked = true
            return
        }
        Task {
            try? await Task.sleep(for: .milliseconds(380))
            guard step == .scan else { return }
            withAnimation(.linear(duration: 0.8)) { locked = true }
        }
    }

    /// The tank empties as the picks screen comes in.
    private func drain() {
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            withAnimation(.easeOut(duration: 1.6)) { drained = true }
        }
    }

    // MARK: Moving through

    private func advance() {
        if let next = step.next {
            step = next
        } else {
            finish()
        }
    }

    private func back() {
        if let previous = step.previous { step = previous }
    }

    private func finish() {
        answers.save()
        OnboardingAnswers.markCompleted()
        onFinish()
    }
}

extension AnyTransition {
    /// Words rise in from below and drift up out, while the hero phone stays put.
    static var onboardingPage: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 34)),
            removal: .opacity.combined(with: .offset(y: -22))
        )
    }
}

// MARK: - Shared pieces

/// Back button and the pencil line that shows how far along they are.
private struct TopBar: View {
    let step: OnboardingStep
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.bold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 36, height: 36)
                    .background(Theme.surface, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.ink.opacity(0.8), lineWidth: 1.5))
            }
            .opacity(step.canGoBack ? 1 : 0)
            .disabled(!step.canGoBack)
            .accessibilityLabel("Back")

            PencilProgress(fraction: step.progress)
                .frame(height: 14)
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.trailing, 48)
    }
}

/// A dashed track with an inked line drawn along it to `fraction`.
private struct PencilProgress: View {
    var fraction: Double
    fileprivate static let design = CGSize(width: 300, height: 14)

    var body: some View {
        ZStack {
            Rectangle()
                .stroke(Theme.ink.opacity(0.2), style: StrokeStyle(lineWidth: 2, dash: [4, 5]))
                .frame(height: 1)
            BoilPoseReader { pose in
                PencilLine(fraction: fraction, pose: pose)
                    .stroke(Theme.ink, style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step progress")
        .accessibilityValue("\(Int(fraction * 100)) percent")
    }

    private struct PencilLine: Shape {
        var fraction: Double
        let pose: Int

        var animatableData: Double {
            get { fraction }
            set { fraction = newValue }
        }

        func path(in rect: CGRect) -> Path {
            let line = Sketch.boil(Sketch.curve([
                CGPoint(x: 0, y: 7), CGPoint(x: 100, y: 6), CGPoint(x: 200, y: 8), CGPoint(x: 300, y: 7),
            ], wobble: 0.9, seed: 900), pose: pose, amount: 0.6)
            var drawn = line.applying(DesignSpace.transform(PencilProgress.design, into: rect)).trimmedPath(from: 0, to: fraction)
            if let tip = drawn.currentPoint {
                drawn.addEllipse(in: CGRect(x: tip.x - 2.5, y: tip.y - 2.5, width: 5, height: 5))
            }
            return drawn
        }
    }
}

/// Room for the hero at the top, the step's own content, then words and a button at the bottom.
private struct PageLayout<Content: View, Words: View, Actions: View>: View {
    let top: CGFloat
    @ViewBuilder var content: Content
    @ViewBuilder var words: Words
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: top)
            content
                .frame(maxWidth: .infinity)
            Spacer(minLength: 12)
            VStack(alignment: .leading, spacing: 10) {
                words
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 18)
            VStack(spacing: 10) {
                actions
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }
}

/// A byte count that rolls from one value to another when animated.
struct CountingBytes: View, Animatable {
    var bytes: Double
    var precision: ByteFormatter.Precision = .twoDecimals

    var animatableData: Double {
        get { bytes }
        set { bytes = newValue }
    }

    var body: some View {
        Text(ByteFormatter.string(Int64(max(bytes, 0)), precision: precision))
            .monospacedDigit()
            .contentTransition(.identity)
    }
}

// MARK: - 1. Hook

/// The person's own phone filling up (the hero), with their real free space.
private struct HookPage: View {
    let top: CGFloat
    let onNext: () -> Void
    @Environment(AppModel.self) private var model
    @State private var progress: CGFloat = 0

    var body: some View {
        let snapshot = model.deviceStorage
        PageLayout(top: top) {
            EmptyView()
        } words: {
            Text(headline(snapshot))
                .font(.display(42))
                .boiling()
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let snapshot {
                Text("\(ByteFormatter.string(snapshot.availableBytes, precision: .twoDecimals)) left of \(ByteFormatter.string(snapshot.advertisedCapacityBytes))")
                    .font(.hand(21))
                    .foregroundStyle(Theme.accent)
                    .handwritten(progress, start: 0.6, length: 0.25)
            }
            Text("Find what's taking the space, and get it back without losing a single memory.")
                .font(.body)
                .foregroundStyle(.secondary)
                .settlesIn(progress, start: 0.66, length: 0.18)
        } actions: {
            Button("Let's get it back", action: onNext)
                .buttonStyle(.sticker)
                .inkedIn(progress, start: 0.7, length: 0.3, radius: 16, seed: 41)
        }
        .drawing($progress, duration: 2.6)
        .task { await model.refreshDeviceStorage() }
    }

    private func headline(_ snapshot: StorageSnapshot?) -> String {
        guard let snapshot else { return "Your iPhone,\nwith room to breathe." }
        let used = snapshot.usedFraction
        let percent = Int((used * 100).rounded())
        return used >= 0.7 ? "Your iPhone is\n\(percent)% full." : "Let's keep your\niPhone roomy."
    }
}

// MARK: - 2. The pain

/// The alerts everyone with a full phone knows, falling out of the hero
/// phone one after another, then how little room is really left.
private struct PainPage: View {
    let top: CGFloat
    let onNext: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = 0
    @State private var progress: CGFloat = 0

    private struct SystemAlert: Identifiable {
        let id: Int
        let symbol: String
        let title: String
        let body: String
    }

    private static let alerts: [SystemAlert] = [
        SystemAlert(id: 0, symbol: "gearshape.fill", title: "iPhone Storage Full",
                    body: "You can manage your storage in Settings."),
        SystemAlert(id: 1, symbol: "camera.fill", title: "Cannot Take Photo",
                    body: "There is not enough available storage to take a photo."),
        SystemAlert(id: 2, symbol: "arrow.down.circle.fill", title: "Unable to Download Update",
                    body: "This update needs more storage than you have free."),
    ]

    var body: some View {
        PageLayout(top: top) {
            // Newest on top, like the Lock Screen; each drops out of the phone above.
            VStack(spacing: -6) {
                ForEach(Self.alerts.prefix(shown).reversed()) { alert in
                    AlertCard(symbol: alert.symbol, title: alert.title, message: alert.body)
                        .rotationEffect(.degrees(alert.id == 1 ? 1.4 : -1.2))
                        .zIndex(Double(alert.id))
                        .transition(.asymmetric(
                            insertion: .offset(y: -90).combined(with: .scale(scale: 0.5, anchor: .top)).combined(with: .opacity),
                            removal: .opacity
                        ))
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
        } words: {
            Text("Sound familiar?")
                .font(.display(40))
                .boiling()
                .accessibilityAddTraits(.isHeader)
            if let runway {
                Text(runwayText(runway))
                    .font(.hand(20))
                    .foregroundStyle(Theme.tomato)
                    .fixedSize(horizontal: false, vertical: true)
                    .handwritten(progress, start: 0.3, length: 0.4)
            }
        } actions: {
            // Drawn in once the last alert has landed.
            Button("Make it stop", action: onNext)
                .buttonStyle(.sticker)
                .inkedIn(progress, start: 0, length: 0.42, radius: 16, seed: 43)
            Text(scanNote)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .settlesIn(progress, start: 0.28, length: 0.25)
        }
        .task { await play() }
        .task { await model.refreshPhotoAccess() }
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.8), trigger: shown)
    }

    /// The Photos permission, explained before iOS asks for it.
    private var scanNote: String {
        let scan = "Next, a quick scan of your \u{201C}\(TestMode.albumName)\u{201D} album. Nothing leaves your iPhone, and nothing is deleted unless you say so."
        guard model.photoAccess == .notDetermined else { return scan }
        return scan + " iOS will ask for Photos access: choose \u{201C}Allow Full Access\u{201D}."
    }

    private var runway: StorageRunway? {
        model.deviceStorage.map { StorageRunway(availableBytes: $0.availableBytes) }
    }

    private func runwayText(_ runway: StorageRunway) -> String {
        let photos = "about \(runway.photos.formatted()) more \(runway.photos == 1 ? "photo" : "photos")"
        guard runway.videoMinutes > 0 else { return "You've got room for \(photos). That's it." }
        let minutes = runway.videoMinutes == 1 ? "1 minute" : "\(runway.videoMinutes.formatted()) minutes"
        return "You've got room for \(photos), or \(minutes) of 4K video."
    }

    private func play() async {
        try? await Task.sleep(for: .milliseconds(380))
        for index in Self.alerts.indices {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.68)) { shown = index + 1 }
            // A shorter beat after the last one, so the button isn't kept waiting.
            try? await Task.sleep(for: .milliseconds(index == Self.alerts.count - 1 ? 320 : 620))
        }
        // The button is drawn, then the note under it and the handwritten line.
        guard !reduceMotion else {
            progress = 1
            return
        }
        withAnimation(.linear(duration: 1.4)) { progress = 1 }
    }
}

/// A storage warning, drawn on paper. No app name or timestamp, so it reads
/// as an illustration rather than a real iOS notification.
private struct AlertCard: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 36, height: 36)
                .background(Theme.well, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.ink, lineWidth: 1.4))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .sticker(radius: 20, padding: 12)
        // One flat layer, so the ink shadow doesn't show through the card as it drops in.
        .compositingGroup()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 3. The scan, printed out of the phone, and where the space went

private struct ScanPage: View {
    let top: CGFloat
    let onDone: ([Suggestion]?) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    private enum Phase: Equatable {
        case reading
        case printing
        case done
        case denied
        case problem(String)
        case empty
    }

    private struct Line: Identifiable, Equatable {
        let id: String
        let title: String
        let detail: String
        let bytes: Int64
        var isTotal = false
    }

    @State private var phase: Phase = .reading
    @State private var lines: [Line] = []
    @State private var shown = 0
    @State private var run = 0
    @State private var printTick = 0
    @State private var bloat: Bloat?
    @State private var found: [Suggestion] = []

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: top - 10)
            switch phase {
            case .reading, .printing, .done:
                receipt
                if phase == .done, let bloat {
                    BloatSummary(bloat: bloat)
                        .transition(.opacity.combined(with: .offset(y: 20)))
                }
            case .denied:
                notice(
                    illustration: .lock,
                    title: "Photos access is off",
                    message: "SimpleShrink needs to see your \u{201C}\(TestMode.albumName)\u{201D} album to find space. You can turn access on in Settings.",
                    primary: ("Open Settings", openSettings)
                )
            case .problem(let message):
                notice(illustration: .emptyBox, title: "Couldn't scan yet", message: message, primary: ("Scan again", { run += 1 }))
            case .empty:
                notice(
                    illustration: .emptyBox,
                    title: "Nothing to scan yet",
                    message: "Your \u{201C}\(TestMode.albumName)\u{201D} album is empty. Add some photos and videos to it, then scan from Home.",
                    primary: nil
                )
            }
            Spacer(minLength: 12)
            if phase == .done {
                // Draws itself in rather than fading; the transition would only fade it.
                Button("Show me what to do") { onDone(found) }
                    .buttonStyle(.sticker)
                    .inksIn(duration: 0.7, radius: 16, seed: 45)
                    .transition(.identity)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: phase)
        .task(id: run) { await scan() }
        .sensoryFeedback(.impact(flexibility: .rigid, intensity: 0.6), trigger: printTick)
        .onChange(of: scenePhase) { _, phase in
            // Back from Settings with access turned on: scan straight away.
            if phase == .active, self.phase == .denied { run += 1 }
        }
    }

    // MARK: Receipt

    private var receipt: some View {
        VStack(spacing: 0) {
            // The slot under the phone the receipt comes out of.
            Capsule()
                .fill(Theme.ink)
                .frame(width: 150, height: 10)
                .boilingShape(0.3, seed: 21)
                .zIndex(1)
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Scan receipt")
                        .font(.display(22))
                    Spacer()
                    Text(Date.now.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Text(TestMode.albumName.uppercased())
                    .font(.caption.weight(.heavy).monospaced())
                    .tracking(1)
                    .foregroundStyle(.secondary)
                DashedRule()
                if phase == .reading {
                    ReadingIndicator(text: "reading your album")
                        .padding(.vertical, 18)
                }
                ForEach(Array(lines.prefix(shown))) { line in
                    if line.isTotal { DashedRule() }
                    ReceiptLine(title: line.title, detail: line.detail, bytes: line.bytes, isTotal: line.isTotal,
                                isHighlighted: phase == .done && line.id == bloat?.group.rawValue)
                        .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
                }
                if phase == .printing, model.isAnalyzing, shown >= lines.count {
                    VStack(alignment: .leading, spacing: 6) {
                        ReadingIndicator(text: "looking for duplicates and blurry shots")
                        ProgressView(value: model.analysisProgress)
                            .tint(Theme.accent)
                    }
                    .padding(.vertical, 8)
                }
            }
            .overlay(alignment: .topTrailing) {
                if phase == .done {
                    RubberStamp(top: "scan", main: "done", color: Theme.accent, angle: -8)
                        .boilingShape(seed: 23)
                        .scaleEffect(0.8)
                        .offset(x: 8, y: 22)
                        .transition(.scale(scale: 2.4).combined(with: .opacity))
                }
            }
            .onReceipt(padding: 18)
            .padding(.horizontal, 8)
            .padding(.top, -5)
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: shown)
        .animation(.spring(response: 0.42, dampingFraction: 0.6), value: phase)
    }

    private func notice(illustration: Illustration, title: String, message: String, primary: (String, () -> Void)?) -> some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.display(30))
                .boiling()
                .multilineTextAlignment(.center)
                .padding(.top, 24)
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer(minLength: 10)
            if let primary {
                Button(primary.0, action: primary.1)
                    .buttonStyle(.sticker)
            }
            Button("Continue without a scan") { onDone(nil) }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
        }
    }

    // MARK: Running the scan

    private func scan() async {
        phase = .reading
        lines = []
        shown = 0
        bloat = nil
        found = []
        let started = Date()

        await model.scanTestAlbum()
        // The app may already be scanning from launch; wait for that one instead.
        while model.isScanning { try? await Task.sleep(for: .milliseconds(100)) }

        guard model.photoAccess.canRead else { phase = .denied; return }
        if let error = model.scanError {
            phase = .problem(error.errorDescription ?? "Something went wrong while scanning.")
            return
        }
        guard let scan = model.albumScan, scan.total.count > 0 else { phase = .empty; return }

        // A beat of "reading" even on a tiny album, so the receipt has somewhere to come from.
        let minimum = 1.2 - Date().timeIntervalSince(started)
        if minimum > 0 { try? await Task.sleep(for: .seconds(minimum)) }

        lines = ScanGroup.kinds.filter { scan[$0].count > 0 }.map { group in
            let total = scan[group]
            return Line(id: group.rawValue, title: group.title, detail: "\(total.count)", bytes: total.bytes)
        }
        phase = .printing
        // Measure for duplicates and junk while the lines print.
        async let analysis: Void = model.findJunk()
        for index in lines.indices {
            try? await Task.sleep(for: .milliseconds(420))
            shown = index + 1
            printTick += 1
        }
        await analysis

        lines.append(Line(id: "total", title: "Total", detail: "\(scan.total.count)", bytes: scan.total.bytes, isTotal: true))
        try? await Task.sleep(for: .milliseconds(500))
        shown = lines.count
        printTick += 1
        try? await Task.sleep(for: .milliseconds(450))
        found = model.suggestions
        bloat = Bloat(scan: scan)
        phase = .done
        printTick += 1
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

/// One printed line: name, count, and a size that rolls up as it prints.
private struct ReceiptLine: View {
    let title: String
    let detail: String
    let bytes: Int64
    let isTotal: Bool
    /// The biggest kind of thing in the album, marked once the scan is done.
    var isHighlighted = false
    @State private var shownBytes: Double = 0

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(isTotal ? .display(20) : .subheadline.weight(.semibold))
            if !detail.isEmpty {
                Text("×\(detail)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            CountingBytes(bytes: shownBytes)
                .font(isTotal ? .metric(.title2) : .metric(.subheadline))
                .foregroundStyle(isTotal || isHighlighted ? Theme.accent : Theme.ink)
        }
        .padding(.vertical, isHighlighted ? 4 : 0)
        .padding(.horizontal, isHighlighted ? 8 : 0)
        .background(Theme.mintSoft.opacity(isHighlighted ? 1 : 0), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, isHighlighted ? -8 : 0)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isHighlighted)
        .onAppear {
            withAnimation(.easeOut(duration: isTotal ? 0.9 : 0.4)) { shownBytes = Double(bytes) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(ByteFormatter.accessibilityString(bytes))")
    }
}

/// Handwritten status with dots that tick along.
private struct ReadingIndicator: View {
    let text: String

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.4)) { context in
            let dots = Int(context.date.timeIntervalSinceReferenceDate / 0.4) % 4
            Text(text + String(repeating: ".", count: dots))
                .font(.hand(18))
                .foregroundStyle(Theme.accent)
        }
        .accessibilityLabel(text)
    }
}

/// Under the receipt: the biggest kind of thing, and why it's worth a look.
private struct BloatSummary: View {
    let bloat: Bloat

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(bloat.group.title) take \(bloat.percent)% of it.")
                .font(.display(26))
                .boiling()
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(bloat.why)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 16)
    }
}

// MARK: - 4. Which ones do you want to try?

/// The scan's suggestions, biggest first, as ticks. The top one starts ticked.
/// The options draw themselves in from the top: each one's outline, then the
/// card, then its illustration, with the button last.
private struct PicksPage: View {
    let top: CGFloat
    let suggestions: [Suggestion]
    @Binding var picks: [CleanupMethod]
    let onNext: () -> Void
    @State private var progress: CGFloat = 0

    /// When the first option starts, and how long each takes, as shares of the page's drawing.
    private static let firstRow: CGFloat = 0.14
    private static let rowLength: CGFloat = 0.4

    /// When option `index` starts drawing. Each starts a little after the one
    /// above; with a long list they start closer together, so the last is
    /// still finished by the end.
    private func rowStart(_ index: Int) -> CGFloat {
        let room = 1 - Self.firstRow - Self.rowLength
        let gap = min(0.11, room / CGFloat(max(suggestions.count - 1, 1)))
        return Self.firstRow + CGFloat(index) * gap
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: top)
            Text("here's what would help most")
                .font(.hand(20))
                .foregroundStyle(Theme.accent)
                .handwritten(progress, start: 0, length: 0.2)
            Text("Which ones do you\nwant to try?")
                .font(.display(34))
                .boiling()
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 4)
                .accessibilityAddTraits(.isHeader)
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                        // The row gets the raw progress and its slot: it has to
                        // work its own drawing out frame by frame (see SketchIn.swift).
                        PickRow(
                            suggestion: suggestion,
                            isBest: index == 0,
                            isOn: picks.contains(suggestion.method),
                            tilt: index.isMultiple(of: 2) ? -1 : 1,
                            drawing: progress,
                            drawStart: rowStart(index),
                            drawLength: Self.rowLength,
                            seed: UInt64(index)
                        ) {
                            toggle(suggestion.method)
                        }
                    }
                }
                // Room for the tilt and the "best bet" note.
                .padding(.top, 16)
                .padding(.bottom, 6)
                .padding(.horizontal, 2)
            }
            .scrollBounceBehavior(.basedOnSize)
            Spacer(minLength: 10)
            Text(footer)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 8)
            Button("Let's do it", action: onNext)
                .buttonStyle(.sticker)
                .disabled(picks.isEmpty)
                .opacity(picks.isEmpty ? 0.5 : 1)
                .inkedIn(progress, start: 0.66, length: 0.34, radius: 16, seed: 47)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .drawing($progress, duration: 2.2)
        .sensoryFeedback(.selection, trigger: picks)
        .onAppear {
            if picks.isEmpty, let first = suggestions.first { picks = [first.method] }
        }
    }

    private var pickedBytes: Int64 {
        suggestions.filter { picks.contains($0.method) }.totalBytes
    }

    private var footer: String {
        let source = "estimated from your \u{201C}\(TestMode.albumName)\u{201D} album."
        guard pickedBytes > 0 else { return "Sizes " + source }
        return "Up to \(ByteFormatter.string(pickedBytes, precision: .twoDecimals)) back, " + source
    }

    /// Keeps the picks in the order they're shown.
    private func toggle(_ method: CleanupMethod) {
        if let index = picks.firstIndex(of: method) {
            picks.remove(at: index)
        } else {
            let order = suggestions.map(\.method)
            picks = order.filter { picks.contains($0) || $0 == method }
        }
    }
}

/// One suggestion: what it is, what it could free, and a tick. It draws itself
/// in during its slot of the page's drawing: a pen goes round the card, the
/// card is inked in behind the line, and the illustration is drawn stroke by
/// stroke as the ink reaches it. "Best bet" is stamped on once the card is there.
private struct PickRow: View {
    let suggestion: Suggestion
    let isBest: Bool
    let isOn: Bool
    var tilt: Double = 0
    /// The page's drawing so far, 0 to 1, and this row's slot in it.
    var drawing: CGFloat = 1
    var drawStart: CGFloat = 0
    var drawLength: CGFloat = 1
    var seed: UInt64 = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                IllustrationView(suggestion.method.illustration, size: 40)
                    .drawn(drawing, start: drawStart + drawLength * 0.42, length: drawLength * 0.58)
                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.method.title)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(suggestion.method.pitch)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                if let bytes = suggestion.bytes {
                    Text("\u{2212}" + ByteFormatter.string(bytes, precision: .twoDecimals))
                        .font(.metric(.subheadline))
                        .monospacedDigit()
                        .foregroundStyle(Theme.accent)
                }
                InkCheck(isOn: isOn, size: 24)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sticker(fill: isOn ? Theme.mintSoft : Theme.surface, radius: 18, padding: 12)
        // Before the tilt, so the pen's outline sits on the card whichever way it leans.
        .inkedIn(drawing, start: drawStart, length: drawLength, radius: 18, seed: 60 + seed)
        .overlay(alignment: .topTrailing) {
            if isBest {
                // A solid chip, so it reads over the card's edge in both themes.
                Text("BEST BET")
                    .font(.caption2.weight(.heavy))
                    .tracking(0.8)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.tomato, in: Capsule())
                    .foregroundStyle(.white)
                    .compositingGroup()
                    .rotationEffect(.degrees(-4))
                    .stamped(drawing, at: drawStart + drawLength * 0.92)
                    .offset(x: -12, y: -10)
                    .accessibilityHidden(true)
            }
        }
        .rotationEffect(.degrees(isOn ? tilt : 0))
        .animation(.spring(response: 0.32, dampingFraction: 0.55), value: isOn)
        .accessibilityElement(children: .combine)
        .accessibilityHint(isBest ? "Frees the most space." : "")
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview("Onboarding") {
    OnboardingFlow(onFinish: {})
        .environment(AppModel.preview())
        .environment(PurchaseStore(defaults: UserDefaults(suiteName: "preview")!))
        .tint(Theme.accent)
}

#Preview("Picks") {
    OnboardingFlow(startAt: .picks, sampleSuggestions: Suggestion.sample, onFinish: {})
        .environment(AppModel.preview())
        .environment(PurchaseStore(defaults: UserDefaults(suiteName: "preview")!))
        .tint(Theme.accent)
}
