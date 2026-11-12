import SwiftUI

// Loaders drawn the way the rest of the app is: ink on paper, redrawn by hand
// twelve times a second. Nothing here eases smoothly. Things step from one
// drawing to the next, hold a pose, and pop, like cel animation.

// MARK: - Cel clock

/// Twelve drawings a second. The line boil holds each of its poses for two of
/// them, so a loader shimmers in step with the boiling headlines around it.
enum CelClock {
    static let framesPerSecond: Double = 12

    static func frame(at date: Date) -> Int {
        Int(date.timeIntervalSinceReferenceDate * framesPerSecond)
    }

    static func pose(_ frame: Int) -> Int {
        (frame / 2) % BoilClock.poses
    }
}

/// Hands its content the current cel frame. Reduce Motion gets one still drawing.
struct CelTimeline<Content: View>: View {
    /// The drawing shown when nothing moves.
    var still = 8
    @ViewBuilder var content: (Int) -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            content(still)
        } else {
            TimelineView(.periodic(from: .now, by: 1 / CelClock.framesPerSecond)) { context in
                content(CelClock.frame(at: context.date))
            }
        }
    }
}

// MARK: - Photos under the glass

/// The picture for "looking at each photo": prints slide in from the right,
/// stop under a magnifying glass one at a time, and leave with a tick (kept)
/// or a cross (a copy, a receipt, a blurry shot).
struct PhotoSortScene: View {
    var frame: Int

    static let design = CGSize(width: 252, height: 78)

    var body: some View {
        Canvas { context, size in
            let scale = DesignSpace.scale(Self.design, in: size)
            context.translateBy(x: (size.width - Self.design.width * scale) / 2,
                                y: (size.height - Self.design.height * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            Self.draw(frame: frame, in: context)
        }
        .aspectRatio(Self.design.width / Self.design.height, contentMode: .fit)
        .accessibilityHidden(true)
    }

    // MARK: Timing

    /// Frames each photo gets: a quick slide in, then a hold under the glass.
    private static let cycle = 10
    /// How far along the slide is on its first frames. It lands on the fourth.
    private static let slide: [CGFloat] = [0.12, 0.46, 0.84]
    /// The frame of the hold on which the verdict is stamped.
    private static let stampFrame = 6
    /// Where the glass sits on each frame: lifted while a photo slides in, a
    /// small look around while it's held.
    private static let glassMoves: [CGPoint] = [
        CGPoint(x: 2, y: -5), CGPoint(x: 3, y: -6.5), CGPoint(x: 2, y: -4), CGPoint(x: 0.5, y: -1.5),
        CGPoint(x: 0, y: 0), CGPoint(x: -2, y: 1), CGPoint(x: 1.5, y: -1), CGPoint(x: 0, y: 0.5),
        CGPoint(x: -1, y: 0), CGPoint(x: 0.5, y: -0.5),
    ]

    private static let spacing: CGFloat = 52
    private static let glass = CGPoint(x: 126, y: 37)
    private static let printSize = CGSize(width: 36, height: 29)
    /// Always dark: it sits on mint or tomato in both light and dark mode.
    private static let stampInk = Color(hex: 0x1A1A17)

    // MARK: The reel

    private enum Subject { case hills, portrait, receipt, blur }

    private struct Shot {
        let subject: Subject
        let isJunk: Bool
    }

    /// The photos, in the order they come round. The second of two alike is a copy.
    private static let reel: [Shot] = [
        Shot(subject: .hills, isJunk: false),
        Shot(subject: .hills, isJunk: true),
        Shot(subject: .portrait, isJunk: false),
        Shot(subject: .receipt, isJunk: true),
        Shot(subject: .hills, isJunk: false),
        Shot(subject: .portrait, isJunk: false),
        Shot(subject: .blur, isJunk: true),
        Shot(subject: .portrait, isJunk: false),
        Shot(subject: .portrait, isJunk: true),
    ]

    // MARK: Drawing

    private static func draw(frame: Int, in context: GraphicsContext) {
        let pose = CelClock.pose(frame)
        let phase = frame % cycle
        let turn = frame / cycle
        let slid: CGFloat = phase < slide.count ? slide[phase] : 1
        let ink = StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)

        // The table, and dashes under it that travel with the photos.
        let table = Sketch.boil(Sketch.line(CGPoint(x: 8, y: 59), CGPoint(x: 244, y: 59), wobble: 0.8, seed: 2), pose: pose, amount: 0.5)
        context.stroke(table, with: .color(Theme.ink.opacity(0.3)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        let travelled = (CGFloat(turn % 4) + slid) * spacing
        var dashes = Path()
        var dashX = design.width + 26 - travelled.truncatingRemainder(dividingBy: 26)
        while dashX > 12 {
            if dashX < design.width - 18 {
                dashes.move(to: CGPoint(x: dashX, y: 65))
                dashes.addLine(to: CGPoint(x: dashX + 9, y: 65))
            }
            dashX -= 26
        }
        context.stroke(dashes, with: .color(Theme.ink.opacity(0.18)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))

        // Photos: slot 0 is under the glass, positive slots are still to come.
        var stamps: [(center: CGPoint, shot: Shot, pop: CGFloat, tilt: Double, fade: Double)] = []
        for slot in -3...3 {
            let number = turn - slot
            let x = glass.x + (CGFloat(slot) + 1 - slid) * spacing
            let fade = Double(min(1, max(0, min(x - 6, design.width - 6 - x) / 26)))
            guard fade > 0 else { continue }
            let shot = reel[((number % reel.count) + reel.count) % reel.count]
            let judged = slot < 0 || (slot == 0 && phase >= stampFrame)
            let setAside = judged && shot.isJunk
            let center = CGPoint(x: x, y: glass.y + 3 + (setAside ? 3 : 0))
            let tilt: Double = setAside ? -7 : 0

            var layer = context
            layer.opacity = fade * (setAside ? 0.62 : 1)
            layer.translateBy(x: center.x, y: center.y)
            layer.rotate(by: .degrees(tilt))
            drawPrint(shot, seed: UInt64(((number % 5) + 5) % 5), pose: pose, kept: judged && !shot.isJunk, in: layer, ink: ink)

            if judged {
                var pop: CGFloat = 1
                if slot == 0 {
                    if phase == stampFrame { pop = 1.55 } else if phase == stampFrame + 1 { pop = 0.9 }
                }
                stamps.append((center, shot, pop, tilt, fade))
            }
        }

        drawGlass(at: glassMoves[phase], pose: pose, in: context)

        // Verdicts go on top, so the one under the glass reads through it.
        for stamp in stamps {
            var layer = context
            layer.opacity = stamp.fade
            layer.translateBy(x: stamp.center.x, y: stamp.center.y)
            layer.rotate(by: .degrees(stamp.tilt))
            layer.translateBy(x: printSize.width / 2 - 2, y: -printSize.height / 2 + 1)
            layer.scaleBy(x: stamp.pop, y: stamp.pop)
            drawStamp(junk: stamp.shot.isJunk, pose: pose, in: layer)
        }

        // The moment it's stamped: three quick lines flying off.
        if phase == stampFrame || phase == stampFrame + 1 {
            let from: CGFloat = phase == stampFrame ? 11 : 15
            let to: CGFloat = phase == stampFrame ? 16 : 19
            let origin = CGPoint(x: glass.x + printSize.width / 2 - 2, y: glass.y + 3 - printSize.height / 2 + 1)
            var burst = Path()
            for degrees in [-100.0, -45.0, 10.0] {
                let angle = degrees * .pi / 180
                burst.move(to: CGPoint(x: origin.x + CGFloat(cos(angle)) * from, y: origin.y + CGFloat(sin(angle)) * from))
                burst.addLine(to: CGPoint(x: origin.x + CGFloat(cos(angle)) * to, y: origin.y + CGFloat(sin(angle)) * to))
            }
            context.stroke(burst, with: .color(Theme.ink), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
        }
    }

    /// One print, centered on the origin.
    private static func drawPrint(_ shot: Shot, seed: UInt64, pose: Int, kept: Bool, in context: GraphicsContext, ink: StrokeStyle) {
        let rect = CGRect(x: -printSize.width / 2, y: -printSize.height / 2, width: printSize.width, height: printSize.height)
        let outline = Sketch.boil(Sketch.box(rect, radius: 4, wobble: 0.7, seed: 40 + seed), pose: pose, amount: 0.55)
        // Mint sits off-register behind a keeper, like the app's other prints.
        if kept {
            context.fill(outline.offsetBy(dx: -2.5, dy: 3), with: .color(Theme.mint))
        }
        context.fill(outline, with: .color(Theme.illustrationPaper))

        var picture = Path()
        switch shot.subject {
        case .hills:
            picture.addPath(Sketch.curve([
                CGPoint(x: -14, y: 9), CGPoint(x: -6, y: -1), CGPoint(x: -1, y: 5), CGPoint(x: 5, y: -3), CGPoint(x: 14, y: 9),
            ], wobble: 0.5, seed: 50 + seed))
            picture.addPath(Sketch.box(CGRect(x: 6, y: -11, width: 6, height: 6), radius: 3, wobble: 0.3, seed: 51 + seed))
        case .portrait:
            picture.addPath(Sketch.box(CGRect(x: -4.5, y: -10, width: 9, height: 9), radius: 4.5, wobble: 0.3, seed: 52 + seed))
            picture.addPath(Sketch.curve([
                CGPoint(x: -10, y: 11), CGPoint(x: -7, y: 3), CGPoint(x: 0, y: 1.5), CGPoint(x: 7, y: 3), CGPoint(x: 10, y: 11),
            ], wobble: 0.5, seed: 53 + seed))
        case .receipt:
            let widths: [CGFloat] = [20, 14, 18, 9]
            for (row, width) in widths.enumerated() {
                let y = -8 + CGFloat(row) * 5.4
                picture.addPath(Sketch.line(CGPoint(x: -11, y: y), CGPoint(x: -11 + width, y: y), wobble: 0.4, seed: 54 + UInt64(row)))
            }
        case .blur:
            picture.addPath(Sketch.curve([
                CGPoint(x: -12, y: 4), CGPoint(x: -8, y: -7), CGPoint(x: -4, y: 6), CGPoint(x: 0, y: -7),
                CGPoint(x: 4, y: 6), CGPoint(x: 8, y: -7), CGPoint(x: 12, y: 3),
            ], wobble: 0.8, seed: 58 + seed))
        }
        let thin = StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
        context.stroke(Sketch.boil(picture, pose: pose, amount: 0.4), with: .color(Theme.ink.opacity(0.75)), style: thin)
        context.stroke(outline, with: .color(Theme.ink), style: ink)
    }

    /// The tick or cross on a print's corner, centered on the origin.
    private static func drawStamp(junk: Bool, pose: Int, in context: GraphicsContext) {
        let badge = Sketch.boil(Sketch.box(CGRect(x: -7.5, y: -7.5, width: 15, height: 15), radius: 7.5, wobble: 0.35, seed: 61), pose: pose, amount: 0.3)
        context.fill(badge, with: .color(junk ? Theme.tomato : Theme.mint))
        context.stroke(badge, with: .color(Theme.ink), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        var glyph = Path()
        if junk {
            glyph.addPath(Sketch.line(CGPoint(x: -3, y: -3), CGPoint(x: 3, y: 3), wobble: 0.3, seed: 62))
            glyph.addPath(Sketch.line(CGPoint(x: 3, y: -3), CGPoint(x: -3, y: 3), wobble: 0.3, seed: 63))
        } else {
            glyph.addPath(Sketch.check(in: CGRect(x: -3.8, y: -2.6, width: 7.8, height: 5.6), seed: 64))
        }
        context.stroke(glyph, with: .color(stampInk), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }

    private static func drawGlass(at move: CGPoint, pose: Int, in context: GraphicsContext) {
        var layer = context
        layer.translateBy(x: glass.x + move.x, y: glass.y + move.y)
        let radius: CGFloat = 21
        let ring = Sketch.boil(
            Sketch.box(CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2), radius: radius, wobble: 0.5, seed: 31),
            pose: pose, amount: 0.5
        )
        layer.fill(ring, with: .color(Theme.mintSoft.opacity(0.45)))
        let handle = Sketch.boil(Sketch.line(CGPoint(x: 15.5, y: 15.5), CGPoint(x: 26, y: 26), wobble: 0.4, seed: 33), pose: pose, amount: 0.4)
        layer.stroke(handle, with: .color(Theme.ink), style: StrokeStyle(lineWidth: 6, lineCap: .round))
        layer.stroke(ring, with: .color(Theme.ink), style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
        // A glint on the upper left of the glass.
        var glint = Path()
        glint.addArc(center: .zero, radius: radius - 5.5, startAngle: .degrees(196), endAngle: .degrees(246), clockwise: false)
        layer.stroke(Sketch.boil(glint, pose: pose, amount: 0.4), with: .color(Theme.ink.opacity(0.55)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
    }
}

// MARK: - Progress bar

/// A hand-inked progress bar: a wobbly outline on a sticker shadow, filled with
/// mint and pencil hatching that marches while the work goes on. With no
/// `progress` it shows a block travelling across instead, for work with no
/// telling how long is left.
struct SketchProgressBar: View {
    /// 0 to 1, or nil when there's nothing to count.
    var progress: Double?
    var frame: Int

    private static let hatchInk = Color(hex: 0x1A1A17)

    var body: some View {
        Canvas { context, size in
            let pose = CelClock.pose(frame)
            // Room on the left and below for the offset shadow.
            let track = CGRect(x: 4, y: 2, width: max(size.width - 6, 10), height: max(size.height - 8, 6))
            let outline = Sketch.boil(Sketch.box(track, radius: track.height / 2, wobble: 0.7, seed: 5), pose: pose, amount: 0.5)
            context.fill(outline.offsetBy(dx: -2.5, dy: 3.5), with: .color(Theme.ink))
            context.fill(outline, with: .color(Theme.surface))

            let filled: CGRect
            if let progress {
                let share = CGFloat(min(1, max(0, progress)))
                // The first sliver shows as soon as there's any progress at all.
                let width = share > 0 ? max(track.height * 0.7, track.width * share) : 0
                filled = CGRect(x: track.minX, y: track.minY, width: width, height: track.height)
            } else {
                let steps = 18
                let block = track.width * 0.3
                let x = track.minX - block + (track.width + block) * CGFloat(frame % steps) / CGFloat(steps)
                filled = CGRect(x: x, y: track.minY, width: block, height: track.height)
            }

            if filled.width > 0 {
                var inside = context
                inside.clip(to: outline)
                inside.fill(Path(filled), with: .color(Theme.mint))

                var hatch = Path()
                let gap: CGFloat = 9
                let lean = track.height * 0.9
                var x = track.minX - lean - gap + CGFloat(frame % 9)
                while x < filled.maxX {
                    hatch.move(to: CGPoint(x: x, y: track.maxY))
                    hatch.addLine(to: CGPoint(x: x + lean, y: track.minY))
                    x += gap
                }
                var hatched = inside
                hatched.clip(to: Path(filled))
                hatched.stroke(hatch, with: .color(Self.hatchInk.opacity(0.26)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))

                // Where the ink has got to.
                for edge in [filled.minX, filled.maxX] where edge > track.minX + 2 && edge < track.maxX - 2 {
                    let line = Sketch.line(CGPoint(x: edge, y: track.minY), CGPoint(x: edge, y: track.maxY), wobble: 0.5, seed: 7 + UInt64(pose))
                    inside.stroke(line, with: .color(Theme.ink), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                }
            }
            context.stroke(outline, with: .color(Theme.ink), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .frame(height: 22)
        .accessibilityHidden(true)
    }
}

// MARK: - Analysis loader

/// The loader for anything that looks through photos: the glass at work, a
/// progress bar, a handwritten line on what's happening right now, and a
/// caption underneath.
struct AnalysisLoader: View {
    /// 0 to 1, or nil for a step that can't be counted.
    var progress: Double?
    /// What's happening right now, in a few words.
    var status: String
    var caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CelTimeline { frame in
                VStack(spacing: 6) {
                    PhotoSortScene(frame: frame)
                        .frame(maxHeight: 96)
                        .frame(maxWidth: .infinity)
                    SketchProgressBar(progress: progress, frame: frame)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(status)
                    .font(.hand(17))
                    .foregroundStyle(Theme.accent)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if let progress {
                    Text("\(Self.percent(progress))%")
                        .font(.hand(19))
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink)
                }
            }
            .padding(.top, 2)
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card(padding: 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(status). \(caption)")
        .accessibilityValue(progress.map { "\(Self.percent($0)) percent" } ?? "Working")
    }

    private static func percent(_ progress: Double) -> Int {
        Int((min(1, max(0, progress)) * 100).rounded(.down))
    }
}

/// The photo-check loader, reading the model's stage and counts itself so a
/// parent screen isn't redrawn on every measured photo.
struct PhotoAnalysisLoader: View {
    @Environment(AppModel.self) private var model
    var caption: String

    var body: some View {
        AnalysisLoader(progress: progress, status: status, caption: caption)
    }

    private var progress: Double? {
        switch model.analysisStage {
        case .measuring where model.analysisTotal > 0: model.analysisProgress
        case .idle where model.isAnalyzing: model.analysisProgress
        case .preparing, .comparing, .idle, .measuring: nil
        }
    }

    private var status: String {
        switch model.analysisStage {
        case .preparing: "getting ready"
        case .comparing: "comparing them for duplicates"
        case .measuring where model.analysisTotal > 0:
            "\(Self.count(model.analysisDone)) of \(Self.count(model.analysisTotal)) photos checked"
        case .measuring, .idle:
            model.isAnalyzing ? "looking at each photo" : "getting ready"
        }
    }

    private static func count(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }
}

/// Same idea for the Live Photos check, which has its own progress.
struct LiveAnalysisLoader: View {
    @Environment(AppModel.self) private var model
    var caption: String

    var body: some View {
        AnalysisLoader(
            progress: model.liveAnalysisProgress,
            status: model.liveCheckFinished
                ? "Live Photos checked"
                : "checking Live Photos",
            caption: caption
        )
    }
}

// MARK: - Spinner

/// A small "working" mark for buttons and placeholders: a stroke of ink
/// chasing round a pencilled circle, one step per drawing.
struct SketchSpinner: View {
    var size: CGFloat = 22
    var tint: Color = Theme.ink

    var body: some View {
        CelTimeline(still: 2) { frame in
            Canvas { context, canvas in
                let side = min(canvas.width, canvas.height)
                let pose = CelClock.pose(frame)
                let center = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
                let radius = side * 0.36
                let wobble = side * 0.018

                let ring = Sketch.box(
                    CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2),
                    radius: radius, wobble: wobble, seed: 3
                )
                context.stroke(Sketch.boil(ring, pose: pose, amount: wobble), with: .color(tint.opacity(0.2)),
                               style: StrokeStyle(lineWidth: side * 0.1, lineCap: .round, lineJoin: .round))

                // Twelve stops to a turn, so it goes round once a second.
                let head = Double(frame % 12) / 12 * 2 * .pi - .pi / 2
                let sweep = 2.0
                let points = (0...6).map { step -> CGPoint in
                    let angle = head - sweep + sweep * Double(step) / 6
                    return CGPoint(x: center.x + CGFloat(cos(angle)) * radius, y: center.y + CGFloat(sin(angle)) * radius)
                }
                context.stroke(Sketch.curve(points, wobble: wobble, seed: 11 + UInt64(pose)), with: .color(tint),
                               style: StrokeStyle(lineWidth: side * 0.14, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("Working")
    }
}
