import StorageCore
import SwiftUI

/// Walks through one other-app guide with drawings that ink themselves in, then
/// measures free space against the reading taken when the guide opened. The
/// person goes back and forth to the other app, so returning re-measures but
/// stays on the same step.
struct OtherAppGuideView: View {
    let guide: OtherAppGuide

    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    /// 0 is the intro, then one page per step, then the measurement.
    @State private var page = 0
    @State private var forward = true
    @State private var progress: CGFloat = 0
    @State private var couldNotOpen = false

    private var steps: [OtherAppGuide.Step] { guide.steps }
    private var measurePage: Int { steps.count + 1 }
    private var freed: Int64 { model.guideFreedBytes }
    private var freedCounts: Bool { freed >= FreedLedger.noiseFloor }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ZStack {
                content
                    .id(page)
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
        .drawing($progress, duration: page == 0 ? 2.2 : 3.4, key: page)
        .task { await model.startMeasuring(guide) }
        .task(id: page) {
            if page == measurePage { await model.checkGuide() }
        }
        .onChange(of: scenePhase) { _, phase in
            // Back from the other app: measure again, without moving the person off their step.
            if phase == .active { Task { await model.checkGuide() } }
        }
        .alert("Couldn't open \(guide.title)", isPresented: $couldNotOpen) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(guide == .whatsapp ? "WhatsApp doesn't seem to be installed on this iPhone." : "Open it from your Home Screen instead.")
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                model.closeOtherAppGuide()
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
            PageDots(count: measurePage + 1, current: page)
            Spacer()
            // Space back so far, so it shows while the person is still going through the steps.
            if freedCounts, page != measurePage {
                Text("+" + ByteFormatter.string(freed, precision: .twoDecimals))
                    .font(.metric(.subheadline))
                    .monospacedDigit()
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(Theme.mintSoft, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.ink, lineWidth: 1.2))
                    .accessibilityLabel("\(ByteFormatter.accessibilityString(freed, precision: .twoDecimals)) freed so far")
                    .transition(.scale.combined(with: .opacity))
            } else {
                Color.clear.frame(width: 40, height: 40)
            }
        }
        .animation(.snappy, value: freedCounts)
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: Pages

    @ViewBuilder
    private var content: some View {
        if page == 0 {
            introPage
        } else if page == measurePage {
            GuideMeasurePage(guide: guide, progress: progress)
        } else {
            stepPage(steps[page - 1], number: page)
        }
    }

    private var introPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("we'll show you how")
                    .font(.hand(21))
                    .foregroundStyle(Theme.accent)
                    .handwritten(progress, start: 0, length: 0.2)
                HStack(alignment: .center, spacing: 14) {
                    IllustrationView(guide.illustration, size: 60)
                    Text(guide.title)
                        .font(.display(34))
                        .boiling()
                        .tracking(-1.1)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }
                Text(guide.intro)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(index + 1)")
                                .font(.hand(20))
                                .foregroundStyle(Theme.accent)
                                .frame(width: 20)
                            Text(step.title)
                                .font(.subheadline.weight(.medium))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    DashedRule()
                    HStack(spacing: 10) {
                        Image(systemName: "gauge.with.dots.needle.33percent")
                            .foregroundStyle(Theme.accent)
                        Text("Storage App measures free space now, and again at the end.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .sticker(radius: 24, padding: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
    }

    private func stepPage(_ step: OtherAppGuide.Step, number: Int) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    Text("\(number)")
                        .font(.hand(26))
                        .frame(width: 44, height: 44)
                        .overlay(Circle().strokeBorder(Theme.ink, lineWidth: 2.2))
                        .handwritten(progress, start: 0, length: 0.15)
                        .accessibilityHidden(true)
                    Text(step.title)
                        .font(.display(28))
                        .boiling()
                        .tracking(-0.9)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }
                SketchCanvas(marks: step.scene, progress: progress)
                    .padding(.vertical, 18)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity)
                    .sticker(fill: Theme.surface, radius: 26, padding: 6)
                    .rotationEffect(.degrees(number.isMultiple(of: 2) ? -0.6 : 0.7))
                Text(step.note)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
                if let warning = step.warning {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.tomato)
                        Text(warning)
                            .font(.subheadline.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .sticker(fill: Theme.surface, radius: 16, padding: 12)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .contain)
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 10) {
            if page == measurePage {
                Button(freedCounts ? "Done" : "Close for Now") { model.closeOtherAppGuide() }
                    .buttonStyle(.sticker)
                Button("Show the Steps Again") {
                    forward = false
                    withAnimation(.snappy) { page = 1 }
                }
                .buttonStyle(.soft)
            } else if page > 0, steps[page - 1].opens {
                Button(action: openDestination) {
                    Label(guide.destination.label, systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.sticker)
                Button("Next") { go(+1) }
                    .buttonStyle(.soft)
                if let hint = guide.destination.hint {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Button(page == 0 ? "Show Me" : page == steps.count ? "I'm Done, Measure" : "Next") { go(+1) }
                    .buttonStyle(.sticker)
                if page > 0 {
                    Button("Back") { go(-1) }
                        .buttonStyle(.soft)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private func openDestination() {
        guard let url = guide.destination.url else { return }
        openURL(url) { accepted in
            if !accepted { couldNotOpen = true }
        }
    }

    private func go(_ delta: Int) {
        let target = page + delta
        guard (0...measurePage).contains(target) else { return }
        forward = delta > 0
        withAnimation(.snappy(duration: 0.35)) { page = target }
    }
}

// MARK: - Measure page

/// Free space now versus when the guide opened.
private struct GuideMeasurePage: View {
    let guide: OtherAppGuide
    let progress: CGFloat
    @Environment(AppModel.self) private var model

    var body: some View {
        let freed = model.guideFreedBytes
        let done = freed >= FreedLedger.noiseFloor
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(done ? "there it is" : "measured just now")
                    .font(.hand(21))
                    .foregroundStyle(Theme.accent)
                    .handwritten(progress, start: 0, length: 0.2)
                Text(done ? "You freed space in \(guide.title)" : "No clear change yet")
                    .font(.display(34))
                    .boiling()
                    .tracking(-1.1)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                VStack(alignment: .leading, spacing: 10) {
                    Text("FREE SPACE BACK")
                        .font(.caption2.weight(.bold))
                        .tracking(1.8)
                        .foregroundStyle(.secondary)
                    SizeText(bytes: freed, style: .largeTitle, unitStyle: .title2, precision: .twoDecimals)
                        .contentTransition(.numericText())
                        .animation(.easeOut(duration: 0.8), value: freed)
                        .accessibilityLabel(ByteFormatter.accessibilityString(freed, precision: .twoDecimals))
                    DrawnStroke(path: Sketch.scribble(width: 200, at: CGPoint(x: 6, y: 10), seed: 1300), design: CGSize(width: 220, height: 20), progress: progress, start: 0.3, length: 0.3)
                        .stroke(done ? Theme.mint : Theme.ink.opacity(0.2), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 220, height: 20)
                        .accessibilityHidden(true)
                    if let latest = model.deviceStorage {
                        HStack {
                            Text("\(ByteFormatter.string(latest.availableBytes, precision: .twoDecimals)) free now")
                            Spacer()
                            Text("checked \(latest.date.formatted(date: .omitted, time: .standard))")
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
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

                Text(done
                     ? "Counted in your results. If you clear more, come back and measure again."
                     : "Free space moves a little on its own, so changes under \(ByteFormatter.string(FreedLedger.noiseFloor)) aren't counted. \(guide.notBackHint)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    Task { await model.checkGuide() }
                } label: {
                    HStack(spacing: 8) {
                        if model.isCheckingGuide {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text(model.isCheckingGuide ? "Checking Free Space…" : "Measure Again")
                    }
                }
                .buttonStyle(.soft)
                .disabled(model.isCheckingGuide)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .sensoryFeedback(.success, trigger: done)
    }
}

/// Small dots for where you are in the guide.
private struct PageDots: View {
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
