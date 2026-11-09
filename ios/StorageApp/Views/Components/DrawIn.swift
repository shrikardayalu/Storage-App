import SwiftUI

// The app drawing itself onto the page once onboarding ends: the title is
// written in, then each card on Home is outlined in wobbly ink and filled,
// top to bottom, in about three seconds. The outline fades as the real card
// lands under it, so it reads as a sketch turning into the finished thing.

/// How far the first-run drawing has got, from 0 (blank page) to 1 (done).
/// 1 everywhere except right after onboarding.
private struct DrawInProgressKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    var drawInProgress: CGFloat {
        get { self[DrawInProgressKey.self] }
        set { self[DrawInProgressKey.self] = newValue }
    }
}

enum DrawIn {
    /// The whole drawing, start to finish.
    static let duration: Double = 3.1

    /// When section `index` (0 at the top) starts drawing, as a share of the whole.
    static func start(section index: Int) -> CGFloat {
        0.12 + CGFloat(index) * 0.11
    }
}

/// Draws one section in: an ink outline traces its frame, then the content
/// settles in while the outline fades away.
private struct DrawInSection: ViewModifier, Animatable {
    var progress: CGFloat
    let start: CGFloat
    let outlined: Bool
    let seed: UInt64

    /// Share of the whole drawing spent tracing the outline.
    private static let traceLength: CGFloat = 0.26
    /// Share spent bringing the content in, starting partway through the trace.
    private static let fillDelay: CGFloat = 0.16
    private static let fillLength: CGFloat = 0.15

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let fill = sketchStep(progress, start: start + (outlined ? Self.fillDelay : 0), length: Self.fillLength)
        content
            .opacity(Double(fill))
            .blur(radius: (1 - fill) * 4)
            .offset(y: (1 - fill) * 8)
            .overlay {
                if outlined, progress < 1 {
                    GeometryReader { proxy in
                        let size = proxy.size
                        let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
                        DrawnStroke(path: Sketch.box(rect, radius: Theme.cardRadius, wobble: 1.6, seed: seed),
                                    design: size, progress: progress, start: start, length: Self.traceLength)
                            .stroke(Theme.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                            .opacity(Double(1 - fill))
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
    }
}

/// The title, written in left to right with the illustration stamped beside it.
private struct DrawInTitle: ViewModifier, Animatable {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content.handwritten(progress, start: 0, length: 0.16)
    }
}

/// Reads the drawing's progress from the environment for one section.
private struct DrawInReader: ViewModifier {
    let section: Int
    let outlined: Bool
    @Environment(\.drawInProgress) private var progress

    func body(content: Content) -> some View {
        content.modifier(DrawInSection(progress: progress, start: DrawIn.start(section: section),
                                       outlined: outlined, seed: UInt64(section) &* 31 &+ 5))
    }
}

private struct DrawInTitleReader: ViewModifier {
    @Environment(\.drawInProgress) private var progress

    func body(content: Content) -> some View {
        content.modifier(DrawInTitle(progress: progress))
    }
}

extension View {
    /// Draws this section in during the first-run drawing. `section` orders
    /// sections top to bottom; `outlined` traces an ink box around it first.
    func drawsIn(section: Int, outlined: Bool = true) -> some View {
        modifier(DrawInReader(section: section, outlined: outlined))
    }

    /// Writes this title in at the start of the first-run drawing.
    func writesIn() -> some View {
        modifier(DrawInTitleReader())
    }
}
