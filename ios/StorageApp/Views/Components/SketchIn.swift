import SwiftUI

// Pieces of a screen that draw themselves in instead of fading. Each one takes
// the whole drawing's progress plus its own slot in it (`start` and `length`,
// both shares of the whole), and works the slot out frame by frame.
//
// That last part matters: a slot worked out in a plain view's body is only
// seen at the first and last frame, so every piece ends up doing one slow fade
// together, however its slot was set. These are `Animatable`, so SwiftUI hands
// them every frame in between.

/// Draws a sticker (a card or a button) in: a pen traces its outline, then the
/// finished sticker is inked in behind the line from left to right.
struct InkIn: ViewModifier, Animatable {
    var progress: CGFloat
    let start: CGFloat
    let length: CGFloat
    let radius: CGFloat
    let seed: UInt64

    /// Share of the slot the pen spends going round the outline.
    private static let traceLength: CGFloat = 0.55
    /// The ink follows the pen in before the outline has quite closed.
    private static let washStart: CGFloat = 0.4
    private static let washLength: CGFloat = 0.6
    /// How far past its own frame a sticker shows: its shadow, and notes pinned to its corner.
    private static let bleed: CGFloat = 20

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let local = min(1, max(0, (progress - start) / max(length, 0.001)))
        let wash = sketchStep(local, start: Self.washStart, length: Self.washLength)
        content
            // One flat layer, so the ink shadow can't show through the fill
            // while the sticker is only partly there.
            .compositingGroup()
            .mask { InkWash(amount: wash, showsInked: true).padding(-Self.bleed) }
            .overlay {
                if local > 0, local < 1 {
                    GeometryReader { proxy in
                        let size = proxy.size
                        let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
                        DrawnStroke(path: Sketch.box(rect, radius: radius, wobble: 1.3, seed: seed),
                                    design: size, progress: local, start: 0, length: Self.traceLength)
                            .stroke(Theme.ink, style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
                    }
                    // The sketched line gives way to the sticker's own edge as the ink passes.
                    .mask { InkWash(amount: wash, showsInked: false).padding(-Self.bleed) }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
    }
}

/// A wash of ink moving left to right with a soft leading edge, used as a mask.
/// It shows either what the ink has covered, or what it hasn't reached yet.
private struct InkWash: View {
    let amount: CGFloat
    let showsInked: Bool
    /// Width of the soft leading edge, in points.
    private static let edge: CGFloat = 36

    var body: some View {
        if amount <= 0 {
            showsInked ? Color.clear : Color.black
        } else if amount >= 1 {
            showsInked ? Color.black : Color.clear
        } else {
            GeometryReader { proxy in
                let soft = min(0.5, Self.edge / max(proxy.size.width, 1))
                let front = amount * (1 + soft)
                LinearGradient(
                    stops: [
                        .init(color: showsInked ? .black : .clear, location: min(1, max(0, front - soft))),
                        .init(color: showsInked ? .clear : .black, location: min(1, max(0, front))),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
        }
    }
}

/// Brings quiet supporting text in during its slot. Words can't be drawn, so
/// they settle onto the page; the slot keeps them in step with the drawing.
struct SettleIn: ViewModifier, Animatable {
    var progress: CGFloat
    let start: CGFloat
    let length: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let shown = sketchStep(progress, start: start, length: length)
        content
            .opacity(Double(shown))
            .offset(y: (1 - shown) * 6)
    }
}

/// Draws a sticker in on its own clock when it first shows, for one that
/// arrives partway through a screen rather than with it.
private struct InkInOnAppear: ViewModifier {
    let duration: Double
    let radius: CGFloat
    let seed: UInt64
    @State private var progress: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .inkedIn(progress, radius: radius, seed: seed)
            .drawing($progress, duration: duration)
    }
}

extension View {
    /// Draws this sticker in between `start` and `start + length` of a drawing:
    /// outline first, then the sticker itself. `radius` is its corner radius.
    func inkedIn(_ progress: CGFloat, start: CGFloat = 0, length: CGFloat = 1,
                 radius: CGFloat = Theme.cardRadius, seed: UInt64 = 1) -> some View {
        modifier(InkIn(progress: progress, start: start, length: length, radius: radius, seed: seed))
    }

    /// Draws this sticker in by itself as soon as it shows.
    func inksIn(duration: Double = 0.7, radius: CGFloat = Theme.cardRadius, seed: UInt64 = 1) -> some View {
        modifier(InkInOnAppear(duration: duration, radius: radius, seed: seed))
    }

    /// Settles supporting text in between `start` and `start + length` of a drawing.
    func settlesIn(_ progress: CGFloat, start: CGFloat, length: CGFloat = 0.2) -> some View {
        modifier(SettleIn(progress: progress, start: start, length: length))
    }
}
