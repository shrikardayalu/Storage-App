import SwiftUI

// "Line boil": the shimmer of hand-drawn animation, where every frame is
// redrawn by hand and never lands exactly on the last one. Headlines step
// through a few slightly different poses at 6 frames a second, each letter
// nudged and tilted on its own, so the type looks freshly inked on paper
// instead of rendered. Reduce Motion holds a single pose.

/// The boil's shared clock: 6 poses a second, cycling through a few drawings
/// like a cel animator's boil loop. Every boiling view reads the same clock,
/// so a whole screen boils in step.
enum BoilClock {
    /// Faster than this and the boil reads as jitter rather than a slow redraw.
    static let framesPerSecond: Double = 6
    /// Distinct drawings in the loop. Three reads as hand-made; more starts to look like noise.
    static let poses = 3

    static func pose(at date: Date) -> Int {
        Int(date.timeIntervalSinceReferenceDate * framesPerSecond) % poses
    }
}

/// Small repeatable jitter for one letter in one pose.
struct BoilJitter {
    let dx: CGFloat
    let dy: CGFloat
    let degrees: Double

    init(index: Int, pose: Int, amount: CGFloat) {
        var random = SketchRandom(seed: UInt64(index &* 7919 &+ pose &* 104_729 &+ 17))
        dx = random.next() * amount
        dy = random.next() * amount
        degrees = Double(random.next()) * Double(amount) * 0.5
    }
}

/// Draws each glyph at its own jittered position and angle for the current pose.
@available(iOS 18.0, *)
struct BoilTextRenderer: TextRenderer {
    var pose: Int
    /// Largest nudge in points at 17pt; scaled up with the type size, to at most 2.5 times.
    var amount: CGFloat

    var displayPadding: EdgeInsets {
        let pad = amount * 4
        return EdgeInsets(top: pad, leading: pad, bottom: pad, trailing: pad)
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        var index = 0
        for line in layout {
            for run in line {
                for glyph in run {
                    let bounds = glyph.typographicBounds.rect
                    let size = max(bounds.height, 1)
                    let jitter = BoilJitter(index: index, pose: pose, amount: amount * min(size / 17, 2.5))
                    var copy = context
                    copy.translateBy(x: bounds.midX + jitter.dx, y: bounds.midY + jitter.dy)
                    copy.rotate(by: .degrees(jitter.degrees))
                    copy.translateBy(x: -bounds.midX, y: -bounds.midY)
                    copy.draw(glyph)
                    index += 1
                }
            }
        }
    }
}

/// Makes the text inside a view boil. On iOS 17, where letters can't be drawn
/// one by one, the whole block wobbles instead.
struct Boil: ViewModifier {
    /// Kept small: type that moves too much reads as shaky, not hand-made.
    var amount: CGFloat = 0.12
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            posed(content, pose: 0)
        } else {
            TimelineView(.periodic(from: .now, by: 1 / BoilClock.framesPerSecond)) { context in
                posed(content, pose: BoilClock.pose(at: context.date))
            }
        }
    }

    @ViewBuilder
    private func posed(_ content: Content, pose: Int) -> some View {
        if #available(iOS 18.0, *) {
            content.textRenderer(BoilTextRenderer(pose: pose, amount: amount))
        } else {
            let jitter = BoilJitter(index: 0, pose: pose, amount: amount)
            content
                .offset(x: jitter.dx, y: jitter.dy)
                .rotationEffect(.degrees(jitter.degrees * 0.3))
        }
    }
}

/// Wobbles any view (an illustration, a stamp, a number) as one piece, in step with the boiling type.
struct BoilShape: ViewModifier {
    var amount: CGFloat = 0.45
    var seed: Int = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            TimelineView(.periodic(from: .now, by: 1 / BoilClock.framesPerSecond)) { context in
                let jitter = BoilJitter(index: seed, pose: BoilClock.pose(at: context.date), amount: amount)
                content
                    .offset(x: jitter.dx, y: jitter.dy)
                    .rotationEffect(.degrees(jitter.degrees * 0.6))
            }
        }
    }
}

extension View {
    /// Boils the text inside this view at 6 frames a second, letter by letter.
    func boiling(_ amount: CGFloat = 0.12) -> some View {
        modifier(Boil(amount: amount))
    }

    /// Boils this whole view as one drawing.
    func boilingShape(_ amount: CGFloat = 0.45, seed: Int = 0) -> some View {
        modifier(BoilShape(amount: amount, seed: seed))
    }
}

/// The current boil pose, for redrawing ink strokes each frame with `Sketch.boil`.
struct BoilPoseReader<Content: View>: View {
    @ViewBuilder var content: (Int) -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            content(0)
        } else {
            TimelineView(.periodic(from: .now, by: 1 / BoilClock.framesPerSecond)) { context in
                content(BoilClock.pose(at: context.date))
            }
        }
    }
}

extension Sketch {
    /// Moves every point of `path` through a smooth field that shifts with
    /// each boil pose. Neighboring points move together, so a line shimmers
    /// like it was traced again rather than jumping to a new shape.
    /// `amount` is in the path's own units.
    static func boil(_ path: Path, pose: Int, amount: CGFloat = 1) -> Path {
        guard amount > 0 else { return path }
        // The golden angle keeps the poses as far apart as possible.
        let phase = CGFloat(pose) * 2.399_963
        func move(_ p: CGPoint) -> CGPoint {
            CGPoint(
                x: p.x + amount * sin(p.y * 0.11 + phase) * cos(p.x * 0.05 - phase * 0.7),
                y: p.y + amount * cos(p.x * 0.09 + phase * 1.3) * sin(p.y * 0.06 + phase)
            )
        }
        var boiled = Path()
        path.forEach { element in
            switch element {
            case .move(let to): boiled.move(to: move(to))
            case .line(let to): boiled.addLine(to: move(to))
            case .quadCurve(let to, let control): boiled.addQuadCurve(to: move(to), control: move(control))
            case .curve(let to, let c1, let c2): boiled.addCurve(to: move(to), control1: move(c1), control2: move(c2))
            case .closeSubpath: boiled.closeSubpath()
            }
        }
        return boiled
    }
}
