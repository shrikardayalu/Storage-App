import StorageCore
import SwiftUI
import UIKit

/// First run, from the hook to the paywall. See `OnboardingStep` for why the
/// steps come in this order. Every number shown is the person's own: real
/// free space on the hook and the pain screen, a real scan on the receipt,
/// real estimates on the reveal. The shrink demo is the one exception, and
/// says it's an example.
///
/// One drawing, `HeroPhone`, stays on screen the whole way and moves between
/// steps, so the flow reads as one story instead of a stack of slides: the
/// phone fills, the alerts fall out of it, it gets locked, it prints the
/// scan, and it drains as the reveal counts up. Only the words change.
struct OnboardingFlow: View {
    var startAt: OnboardingStep = .hook
    /// Fixed numbers for CI screenshots, which have no library to scan.
    var sampleReveal: RevealNumbers?
    let onFinish: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(PurchaseStore.self) private var purchases
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: OnboardingStep = .hook
    @State private var answers = OnboardingAnswers.load()
    @State private var reveal: RevealNumbers?

    // The hero phone's story so far.
    @State private var drawProgress: CGFloat = 0
    @State private var filled = false
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
                    spills: step == .hook && filled && usedFraction >= 0.7,
                    locked: step == .privacy || step == .scan,
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
            if new == .reveal { drain() }
        }
    }

    @ViewBuilder
    private func page(top: CGFloat) -> some View {
        switch step {
        case .hook:
            HookPage(top: top, onNext: advance)
        case .pain:
            PainPage(top: top, onNext: advance)
        case .goal:
            GoalPage(top: top, answers: $answers, onNext: advance)
        case .shrink:
            ShrinkPage(top: top, onNext: advance)
        case .privacy:
            PrivacyPage(top: top, onNext: advance)
        case .scan:
            ScanPage(top: top) { numbers in
                reveal = numbers
                if let numbers, !numbers.isEmpty {
                    advance()
                } else if showsPaywall {
                    // Nothing found, or no access: skip the reveal, keep the pitch.
                    step = .paywall
                } else {
                    finish()
                }
            }
        case .reveal:
            RevealPage(top: top, numbers: reveal ?? .sample, answers: answers, showsPaywall: showsPaywall, onNext: advance)
        case .paywall:
            PaywallFlow(context: PaywallContext(proBytes: reveal?.proBytes), onDone: finish)
        }
    }

    // MARK: The hero's place and state on each step

    /// Where the phone sits: big on the hook, then tucked above each step's words.
    private func heroFrame(for step: OnboardingStep, in size: CGSize) -> CGRect {
        let share: CGFloat
        switch step {
        case .hook: share = 0.42
        case .pain: share = 0.19
        case .goal: share = 0.16
        case .shrink: share = 0.14
        case .privacy: share = 0.3
        case .scan: share = 0.12
        case .reveal: share = 0.18
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
        case .goal: 4
        case .shrink: -3
        case .reveal: 4
        default: 0
        }
    }

    private var usedFraction: Double { model.deviceStorage?.usedFraction ?? 0.9 }

    /// Empty, then the phone's real fill, then what's left after the reveal's saving.
    private var heroLevel: CGFloat {
        guard filled else { return 0 }
        guard drained, let reveal, let total = model.deviceStorage?.totalBytes, total > 0 else { return CGFloat(usedFraction) }
        return CGFloat(max(0.04, usedFraction - Double(reveal.totalBytes) / Double(total)))
    }

    /// The hook draws the phone in, fills it, then stamps it. Later steps
    /// (screenshot routes) start with the phone already drawn.
    private func begin() {
        step = startAt
        reveal = sampleReveal
        guard startAt == .hook, !reduceMotion else {
            drawProgress = 1
            filled = true
            stamped = usedFraction >= 0.8
            if startAt == .reveal { drain() }
            return
        }
        Task {
            try? await Task.sleep(for: .milliseconds(80))
            withAnimation(.easeInOut(duration: 1.1)) { drawProgress = 1 }
            try? await Task.sleep(for: .milliseconds(750))
            withAnimation(.easeInOut(duration: 1.3)) { filled = true }
            guard usedFraction >= 0.8 else { return }
            try? await Task.sleep(for: .milliseconds(1400))
            withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { stamped = true }
            stampTick += 1
        }
    }

    /// Runs alongside the reveal's count-up, so the tank empties as the number climbs.
    private func drain() {
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            withAnimation(.easeOut(duration: 1.6)) { drained = true }
        }
    }

    // MARK: Moving through

    private var showsPaywall: Bool { purchases.requiresPro }

    private func advance() {
        answers.save()
        if let next = step.next(showsPaywall: showsPaywall) {
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

/// A big selectable choice, as a sticker that tilts a little when picked.
private struct ChoiceSticker: View {
    let symbol: String
    let title: String
    let isOn: Bool
    var tilt: Double = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 30)
                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                InkCheck(isOn: isOn, size: 24)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sticker(fill: isOn ? Theme.mintSoft : Theme.surface, radius: 18, padding: 14)
        .rotationEffect(.degrees(isOn ? tilt : 0))
        .scaleEffect(isOn ? 1.02 : 1)
        .animation(.spring(response: 0.32, dampingFraction: 0.55), value: isOn)
        .accessibilityAddTraits(isOn ? .isSelected : [])
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
                .opacity(sketchStep(progress, start: 0.7, length: 0.2))
        } actions: {
            Button("Let's get it back", action: onNext)
                .buttonStyle(.sticker)
                .opacity(sketchStep(progress, start: 0.8, length: 0.2))
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
    @State private var shown = 0
    @State private var progress: CGFloat = 0

    private struct SystemAlert: Identifiable {
        let id: Int
        let symbol: String
        let app: String
        let title: String
        let body: String
    }

    private static let alerts: [SystemAlert] = [
        SystemAlert(id: 0, symbol: "gearshape.fill", app: "SETTINGS", title: "iPhone Storage Full",
                    body: "You can manage your storage in Settings."),
        SystemAlert(id: 1, symbol: "camera.fill", app: "CAMERA", title: "Cannot Take Photo",
                    body: "There is not enough available storage to take a photo."),
        SystemAlert(id: 2, symbol: "arrow.down.circle.fill", app: "SOFTWARE UPDATE", title: "Unable to Download Update",
                    body: "This update needs more storage than you have free."),
    ]

    var body: some View {
        PageLayout(top: top) {
            // Newest on top, like the Lock Screen; each drops out of the phone above.
            VStack(spacing: -6) {
                ForEach(Self.alerts.prefix(shown).reversed()) { alert in
                    AlertCard(symbol: alert.symbol, app: alert.app, title: alert.title, message: alert.body)
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
            Button("Make it stop", action: onNext)
                .buttonStyle(.sticker)
                .opacity(shown >= Self.alerts.count ? 1 : 0.001)
        }
        .task { await play() }
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.8), trigger: shown)
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
            try? await Task.sleep(for: .milliseconds(620))
        }
        withAnimation(.linear(duration: 1.2)) { progress = 1 }
    }
}

/// A Lock Screen notification, drawn on paper.
private struct AlertCard: View {
    let symbol: String
    let app: String
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
                HStack {
                    Text(app)
                        .font(.caption2.weight(.semibold))
                        .tracking(0.4)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("now")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(title)
                    .font(.subheadline.weight(.bold))
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .sticker(radius: 20, padding: 12)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 3. What it's for

private struct GoalPage: View {
    let top: CGFloat
    @Binding var answers: OnboardingAnswers
    let onNext: () -> Void
    @State private var progress: CGFloat = 0
    @State private var advancing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: top)
            Text("one tap")
                .font(.hand(20))
                .foregroundStyle(Theme.accent)
                .handwritten(progress, start: 0, length: 0.3)
            Text("What do you need\nthe space for?")
                .font(.display(36))
                .boiling()
                .padding(.bottom, 20)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 12) {
                ForEach(Array(SpaceGoal.allCases.enumerated()), id: \.element) { index, goal in
                    ChoiceSticker(symbol: goal.symbol, title: goal.title, isOn: answers.goal == goal,
                                  tilt: index.isMultiple(of: 2) ? -1.2 : 1.2) {
                        pick(goal)
                    }
                    .opacity(sketchStep(progress, start: 0.15 + CGFloat(index) * 0.1, length: 0.2))
                    .offset(y: 18 * (1 - sketchStep(progress, start: 0.15 + CGFloat(index) * 0.1, length: 0.2)))
                }
            }
            Spacer(minLength: 20)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .drawing($progress, duration: 1.2)
        .sensoryFeedback(.selection, trigger: answers.goal)
    }

    /// Picking is the answer: a beat to see the tick, then on.
    private func pick(_ goal: SpaceGoal) {
        guard !advancing else { return }
        answers.goal = goal
        advancing = true
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            onNext()
        }
    }
}

// MARK: - 4. Shrink, don't delete

/// The Pro idea in one moment: a big video squashes down and keeps its stamp.
private struct ShrinkPage: View {
    let top: CGFloat
    let onNext: () -> Void
    @State private var replay = 0
    @State private var stage = 0

    private static let before: Double = 1_240_000_000
    private static let after: Double = 410_000_000

    var body: some View {
        PageLayout(top: top) {
            VStack(spacing: 14) {
                videoCard
                liveCard
                Button {
                    replay += 1
                } label: {
                    Label("watch again", systemImage: "arrow.counterclockwise")
                        .font(.hand(17))
                        .foregroundStyle(Theme.accent)
                }
                .opacity(stage >= 4 ? 1 : 0)
            }
            .padding(.top, 6)
        } words: {
            Text("Shrink it.\nDon't delete it.")
                .font(.display(40))
                .boiling()
                .accessibilityAddTraits(.isHeader)
            Text("Deleting isn't the only way. Storage App can also make big videos and Live Photos smaller, so you keep the memory and get the space.")
                .font(.body)
                .foregroundStyle(.secondary)
            Text("Example sizes. Your own numbers come next.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        } actions: {
            Button("Nice. What about mine?", action: onNext)
                .buttonStyle(.sticker)
        }
        .task(id: replay) { await play() }
        .sensoryFeedback(.impact(weight: .heavy), trigger: stage == 2)
        .sensoryFeedback(.impact(weight: .medium), trigger: stage == 3)
    }

    private var videoCard: some View {
        HStack(spacing: 14) {
            IllustrationView(.video, size: 52)
                .boilingShape(seed: 11)
            VStack(alignment: .leading, spacing: 2) {
                Text("Beach day.mov")
                    .font(.headline)
                Text(stage >= 2 ? "1080p · 2:14" : "4K · 2:14")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 4)
            CountingBytes(bytes: stage >= 2 ? Self.after : Self.before)
                .font(.metric(.title3))
                .foregroundStyle(stage >= 2 ? Theme.accent : Theme.ink)
        }
        .sticker(fill: stage >= 2 ? Theme.mintSoft : Theme.surface, padding: 16)
        // Squash and stretch: squeezed flat, then springs back a bit smaller.
        .scaleEffect(x: stage == 1 ? 1.08 : 1, y: stage == 1 ? 0.62 : (stage >= 2 ? 0.94 : 1), anchor: .bottom)
        .overlay(alignment: .topTrailing) {
            if stage >= 2 {
                RubberStamp(top: "same", main: "video", color: Theme.accent, angle: 10)
                    .boilingShape(seed: 13)
                    .offset(x: 10, y: -26)
                    .transition(.scale(scale: 2.2).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottomLeading) {
            if stage >= 2 {
                Text("\u{2212}67%")
                    .font(.hand(22))
                    .foregroundStyle(Theme.tomato)
                    .boiling()
                    .rotationEffect(.degrees(-8))
                    .offset(x: 8, y: 30)
                    .transition(.opacity)
            }
        }
    }

    private var liveCard: some View {
        HStack(spacing: 14) {
            IllustrationView(.photo, size: 44)
                .boilingShape(seed: 15)
            VStack(alignment: .leading, spacing: 2) {
                Text(stage >= 3 ? "Still photo" : "Live Photo")
                    .font(.headline)
                    .contentTransition(.opacity)
                Text("same picture, no video clip")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            CountingBytes(bytes: stage >= 3 ? 2_300_000 : 5_800_000, precision: .compact)
                .font(.metric(.headline))
                .foregroundStyle(stage >= 3 ? Theme.accent : Theme.ink)
        }
        .sticker(fill: stage >= 3 ? Theme.mintSoft : Theme.surface, padding: 14)
        .padding(.top, 22)
        .opacity(stage >= 3 ? 1 : 0)
        .offset(y: stage >= 3 ? 0 : 24)
    }

    private func play() async {
        stage = 0
        try? await Task.sleep(for: .milliseconds(900))
        withAnimation(.spring(response: 0.22, dampingFraction: 0.5)) { stage = 1 }
        try? await Task.sleep(for: .milliseconds(240))
        withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) { stage = 2 }
        try? await Task.sleep(for: .milliseconds(1100))
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { stage = 3 }
        try? await Task.sleep(for: .milliseconds(900))
        withAnimation(.easeOut) { stage = 4 }
    }
}

// MARK: - 5. Photos permission, explained first

/// The hero phone gets its padlock here.
private struct PrivacyPage: View {
    let top: CGFloat
    let onNext: () -> Void
    @Environment(AppModel.self) private var model
    @State private var progress: CGFloat = 0

    private var promises: [String] {
        [
            "Your photos are never uploaded. Everything is checked right on your iPhone.",
            "Nothing is deleted or changed until you say so.",
            "For now it only reads your \u{201C}\(TestMode.albumName)\u{201D} album.",
        ]
    }

    var body: some View {
        PageLayout(top: top) {
            EmptyView()
        } words: {
            Text("Your photos stay\non your iPhone.")
                .font(.display(36))
                .boiling()
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(promises.enumerated()), id: \.offset) { index, promise in
                    HStack(alignment: .top, spacing: 12) {
                        InkCheck(isOn: progress > 0.3 + CGFloat(index) * 0.18, size: 24)
                        Text(promise)
                            .font(.subheadline.weight(.medium))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .opacity(sketchStep(progress, start: 0.2 + CGFloat(index) * 0.18, length: 0.15))
                }
            }
            .padding(.top, 6)
        } actions: {
            Button(model.photoAccess.canRead ? "Scan my album" : "Allow Photos access", action: onNext)
                .buttonStyle(.sticker)
            if model.photoAccess == .notDetermined {
                Text("iOS asks next. Choose \u{201C}Allow Full Access\u{201D}.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .drawing($progress, duration: 1.8)
        .task { await model.refreshPhotoAccess() }
    }
}

// MARK: - 6. The scan, printed out of the phone

private struct ScanPage: View {
    let top: CGFloat
    let onDone: (RevealNumbers?) -> Void
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

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: top - 10)
            switch phase {
            case .reading, .printing, .done:
                receipt
            case .denied:
                notice(
                    illustration: .lock,
                    title: "Photos access is off",
                    message: "Storage App needs to see your \u{201C}\(TestMode.albumName)\u{201D} album to find space. You can turn access on in Settings.",
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
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
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
                    ReceiptLine(title: line.title, detail: line.detail, bytes: line.bytes, isTotal: line.isTotal)
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
                if phase == .done {
                    HStack {
                        Spacer()
                        RubberStamp(top: "scan", main: "done", color: Theme.accent, angle: -8)
                            .boilingShape(seed: 23)
                            .transition(.scale(scale: 2.4).combined(with: .opacity))
                        Spacer()
                    }
                    .padding(.top, 4)
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

        let numbers = RevealNumbers(freeBytes: model.junkReport?.suggestedBytes ?? 0, proBytes: model.proSaving)
        if let report = model.junkReport, !report.isEmpty {
            lines.append(Line(id: "junk", title: "Duplicates & junk", detail: "\(report.suggestedCount)", bytes: report.suggestedBytes))
            try? await Task.sleep(for: .milliseconds(420))
            shown = lines.count
            printTick += 1
        }
        lines.append(Line(id: "total", title: "Could free", detail: "", bytes: numbers.totalBytes, isTotal: true))
        try? await Task.sleep(for: .milliseconds(500))
        shown = lines.count
        printTick += 1
        try? await Task.sleep(for: .milliseconds(450))
        phase = .done
        printTick += 1
        try? await Task.sleep(for: .milliseconds(1300))
        onDone(numbers)
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
                .foregroundStyle(isTotal ? Theme.accent : Theme.ink)
        }
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

// MARK: - 7. The reveal

/// The number counts up while the hero phone above drains to match.
private struct RevealPage: View {
    let top: CGFloat
    let numbers: RevealNumbers
    let answers: OnboardingAnswers
    let showsPaywall: Bool
    let onNext: () -> Void

    @State private var progress: CGFloat = 0
    @State private var shownBytes: Double = 0
    @State private var confetti = 0
    @State private var settled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: top)
            Text("you could free up")
                .font(.hand(22))
                .foregroundStyle(Theme.accent)
                .handwritten(progress, start: 0, length: 0.15)

            ZStack(alignment: .leading) {
                CountingBytes(bytes: shownBytes)
                    .font(.display(60))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .boiling()
                    .accessibilityLabel(ByteFormatter.accessibilityString(numbers.totalBytes, precision: .twoDecimals))
                InkConfetti(trigger: confetti)
                    .frame(width: 10, height: 10)
                    .offset(x: 110)
            }
            .padding(.vertical, 2)
            .background(alignment: .leading) {
                CircledLoop(progress: progress)
                    .frame(width: 260, height: 90)
                    .offset(x: -18)
            }

            Text(answers.goal?.revealPhrase ?? "without losing a memory")
                .font(.display(22))
                .boiling()
                .padding(.top, 6)
            if numbers.morePhotos > 0 {
                Text("that's room for about \(numbers.morePhotos.formatted()) more photos")
                    .font(.hand(18))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }

            VStack(spacing: 10) {
                SplitRow(illustration: .trash, title: "Delete duplicates & junk", tag: "free", bytes: numbers.freeBytes)
                    .opacity(settled ? 1 : 0)
                    .offset(y: settled ? 0 : 20)
                SplitRow(illustration: .compress, title: "Shrink, keep every memory", tag: "pro", bytes: numbers.proBytes)
                    .opacity(settled ? 1 : 0)
                    .offset(y: settled ? 0 : 28)
            }
            .padding(.top, 16)
            .animation(.spring(response: 0.5, dampingFraction: 0.75), value: settled)

            Spacer(minLength: 12)
            Text("Estimated from your \u{201C}\(TestMode.albumName)\u{201D} album.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 8)
            Button(showsPaywall ? "Get it all back" : "Start cleaning", action: onNext)
                .buttonStyle(.sticker)
                .opacity(settled ? 1 : 0.001)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .drawing($progress, duration: 2)
        .sensoryFeedback(.success, trigger: confetti)
        .task { await play() }
    }

    /// Same timing as the hero's drain, so the number and the tank move together.
    private func play() async {
        try? await Task.sleep(for: .milliseconds(350))
        withAnimation(.easeOut(duration: 1.6)) { shownBytes = Double(numbers.totalBytes) }
        try? await Task.sleep(for: .milliseconds(1500))
        confetti += 1
        settled = true
    }
}

/// A loose pen loop circling the big number.
private struct CircledLoop: View {
    let progress: CGFloat
    private static let design = CGSize(width: 260, height: 90)
    private static let loop = Sketch.loop(around: CGRect(x: 8, y: 8, width: 244, height: 74), seed: 50)

    var body: some View {
        BoilPoseReader { pose in
            DrawnStroke(path: Sketch.boil(Self.loop, pose: pose, amount: 0.8),
                        design: Self.design, progress: progress, start: 0.55, length: 0.3)
                .stroke(Theme.mint, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

/// Free vs Pro, side by side on the reveal.
private struct SplitRow: View {
    let illustration: Illustration
    let title: String
    let tag: String
    let bytes: Int64

    var body: some View {
        HStack(spacing: 12) {
            IllustrationView(illustration, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(tag.uppercased())
                    .font(.caption2.weight(.heavy))
                    .tracking(0.8)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(tag == "pro" ? Theme.mint : Theme.well, in: Capsule())
                    .foregroundStyle(Color(hex: 0x1A1A17))
            }
            Spacer(minLength: 6)
            Text(ByteFormatter.string(bytes, precision: .twoDecimals))
                .font(.metric(.headline))
                .monospacedDigit()
        }
        .sticker(padding: 12)
    }
}

#Preview("Onboarding") {
    OnboardingFlow(onFinish: {})
        .environment(AppModel.preview())
        .environment(PurchaseStore(defaults: UserDefaults(suiteName: "preview")!))
        .tint(Theme.accent)
}

#Preview("Reveal") {
    OnboardingFlow(startAt: .reveal, sampleReveal: .sample, onFinish: {})
        .environment(AppModel.preview())
        .environment(PurchaseStore(defaults: UserDefaults(suiteName: "preview")!))
        .tint(Theme.accent)
}
