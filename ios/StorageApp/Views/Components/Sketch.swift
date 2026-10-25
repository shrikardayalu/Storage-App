import SwiftUI

// Hand-drawn pieces shared with the website's look: wobbly ink strokes that
// draw themselves in, a handwriting font, paper grain, rubber stamps, and torn
// receipts. Strokes are built in a fixed design space and scaled to fit, so a
// scene looks the same on every phone.

// MARK: - Fonts

extension Font {
    /// Handwriting, like the site's notes in the margin.
    static func hand(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom("Noteworthy-Bold", size: size, relativeTo: style)
    }

    /// Heavy, tight headline type, like the site's display face.
    static func display(_ size: CGFloat, relativeTo style: Font.TextStyle = .largeTitle) -> Font {
        .system(size: size, weight: .heavy, design: .default)
    }
}

// MARK: - Wobbly paths

/// Repeatable randomness, so a drawing wobbles the same way every time.
struct SketchRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
    }

    /// A value from -1 to 1.
    mutating func next() -> CGFloat {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return CGFloat(Double((state >> 33) & 0xFFFF) / Double(0xFFFF)) * 2 - 1
    }
}

/// Builders for pen-like paths. Each one jitters its points a little and runs
/// smooth curves through them, so lines look drawn rather than ruled.
enum Sketch {
    /// A smooth wobbly line through `points`.
    static func curve(_ points: [CGPoint], wobble: CGFloat = 1.2, seed: UInt64 = 1, closed: Bool = false) -> Path {
        var random = SketchRandom(seed: seed)
        let jittered = points.map { CGPoint(x: $0.x + random.next() * wobble, y: $0.y + random.next() * wobble) }
        var path = Path()
        guard let first = jittered.first else { return path }
        guard jittered.count > 2 else {
            path.move(to: first)
            if let last = jittered.last { path.addLine(to: last) }
            return path
        }
        path.move(to: first)
        for i in 1..<jittered.count - 1 {
            let mid = CGPoint(x: (jittered[i].x + jittered[i + 1].x) / 2, y: (jittered[i].y + jittered[i + 1].y) / 2)
            path.addQuadCurve(to: mid, control: jittered[i])
        }
        if let last = jittered.last { path.addLine(to: last) }
        if closed {
            // Pens overshoot where they started, so overlap the start a little.
            path.addQuadCurve(to: CGPoint(x: first.x + 4, y: first.y + random.next()), control: first)
        }
        return path
    }

    /// A straight-ish line with a slight bow, split into a few segments.
    static func line(_ a: CGPoint, _ b: CGPoint, wobble: CGFloat = 1.2, seed: UInt64 = 1) -> Path {
        let steps = 4
        let points = (0...steps).map { i -> CGPoint in
            let t = CGFloat(i) / CGFloat(steps)
            return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }
        return curve(points, wobble: wobble, seed: seed)
    }

    /// A rounded rectangle drawn in one pass, starting near the top left.
    static func box(_ rect: CGRect, radius: CGFloat = 10, wobble: CGFloat = 1.4, seed: UInt64 = 1) -> Path {
        let r = min(radius, rect.width / 2, rect.height / 2)
        var points: [CGPoint] = []
        func corner(_ center: CGPoint, from start: Double) {
            for i in 0...3 {
                let angle = (start + Double(i) * 30) * .pi / 180
                points.append(CGPoint(x: center.x + CGFloat(cos(angle)) * r, y: center.y + CGFloat(sin(angle)) * r))
            }
        }
        func edge(_ a: CGPoint, _ b: CGPoint) {
            let length = hypot(b.x - a.x, b.y - a.y)
            let steps = max(1, Int(length / 28))
            for i in 1..<steps {
                let t = CGFloat(i) / CGFloat(steps)
                points.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
            }
        }
        corner(CGPoint(x: rect.minX + r, y: rect.minY + r), from: 180)
        edge(CGPoint(x: rect.minX + r, y: rect.minY), CGPoint(x: rect.maxX - r, y: rect.minY))
        corner(CGPoint(x: rect.maxX - r, y: rect.minY + r), from: 270)
        edge(CGPoint(x: rect.maxX, y: rect.minY + r), CGPoint(x: rect.maxX, y: rect.maxY - r))
        corner(CGPoint(x: rect.maxX - r, y: rect.maxY - r), from: 0)
        edge(CGPoint(x: rect.maxX - r, y: rect.maxY), CGPoint(x: rect.minX + r, y: rect.maxY))
        corner(CGPoint(x: rect.minX + r, y: rect.maxY - r), from: 90)
        edge(CGPoint(x: rect.minX, y: rect.maxY - r), CGPoint(x: rect.minX, y: rect.minY + r))
        return curve(points, wobble: wobble, seed: seed, closed: true)
    }

    /// A loose loop around `rect`, the way you'd circle something on paper.
    /// It goes round a little more than once and doesn't quite meet itself.
    static func loop(around rect: CGRect, turns: Double = 1.18, seed: UInt64 = 3) -> Path {
        var random = SketchRandom(seed: seed)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let count = 26
        let tilt = Double(random.next()) * 0.12
        let points = (0...count).map { i -> CGPoint in
            let t = Double(i) / Double(count)
            let angle = -2.2 + t * turns * 2 * .pi
            let grow = 1 + CGFloat(t) * 0.08 + random.next() * 0.025
            return CGPoint(
                x: center.x + CGFloat(cos(angle + tilt)) * rect.width / 2 * grow,
                y: center.y + CGFloat(sin(angle)) * rect.height / 2 * grow
            )
        }
        return curve(points, wobble: 0.6, seed: seed)
    }

    /// A curved arrow from `start` to `end`. `bend` pushes the curve sideways.
    static func arrow(from start: CGPoint, to end: CGPoint, bend: CGFloat = 24, seed: UInt64 = 5) -> Path {
        let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        let dx = end.x - start.x, dy = end.y - start.y
        let length = max(1, hypot(dx, dy))
        let control = CGPoint(x: mid.x - dy / length * bend, y: mid.y + dx / length * bend)
        let points = (0...8).map { i -> CGPoint in
            let t = CGFloat(i) / 8
            let u = 1 - t
            return CGPoint(
                x: u * u * start.x + 2 * u * t * control.x + t * t * end.x,
                y: u * u * start.y + 2 * u * t * control.y + t * t * end.y
            )
        }
        var path = curve(points, wobble: 0.8, seed: seed)
        // Arrowhead along the curve's final direction.
        let angle = atan2(end.y - control.y, end.x - control.x)
        let size: CGFloat = 11
        let left = CGPoint(x: end.x - cos(angle - 0.5) * size, y: end.y - sin(angle - 0.5) * size)
        let right = CGPoint(x: end.x - cos(angle + 0.5) * size, y: end.y - sin(angle + 0.5) * size)
        path.addPath(curve([left, end, right], wobble: 0.5, seed: seed + 1))
        return path
    }

    /// A quick tick mark.
    static func check(in rect: CGRect, seed: UInt64 = 7) -> Path {
        curve([
            CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.05),
            CGPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.minY),
        ], wobble: 0.6, seed: seed)
    }

    /// A wavy underline, like the site's marker scribble.
    static func scribble(width: CGFloat, at origin: CGPoint, seed: UInt64 = 9) -> Path {
        var path = curve([
            origin,
            CGPoint(x: origin.x + width * 0.3, y: origin.y - 4),
            CGPoint(x: origin.x + width * 0.62, y: origin.y - 2),
            CGPoint(x: origin.x + width, y: origin.y + 2),
        ], wobble: 0.8, seed: seed)
        path.addPath(curve([
            CGPoint(x: origin.x + width * 0.08, y: origin.y + 6),
            CGPoint(x: origin.x + width * 0.5, y: origin.y + 3),
            CGPoint(x: origin.x + width * 0.9, y: origin.y + 6),
        ], wobble: 0.8, seed: seed + 1))
        return path
    }
}

// MARK: - Drawing in

/// Eases a drawing step so the pen speeds up and slows down like a hand.
private func penEase(_ t: CGFloat) -> CGFloat {
    t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
}

/// The share of one step that's done, given the whole drawing's progress.
func sketchStep(_ progress: CGFloat, start: CGFloat, length: CGFloat) -> CGFloat {
    guard length > 0 else { return progress >= start ? 1 : 0 }
    return penEase(min(1, max(0, (progress - start) / length)))
}

/// A path in design space that draws itself as `progress` goes from `start`
/// to `start + length`, with a bead of ink at the pen tip while it moves.
struct DrawnStroke: Shape {
    let path: Path
    let design: CGSize
    var progress: CGFloat
    var start: CGFloat = 0
    var length: CGFloat = 1
    var showsPenTip = true

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let local = sketchStep(progress, start: start, length: length)
        guard local > 0 else { return Path() }
        var drawn = path.applying(DesignSpace.transform(design, into: rect)).trimmedPath(from: 0, to: local)
        if showsPenTip, local < 1, let tip = drawn.currentPoint {
            drawn.addEllipse(in: CGRect(x: tip.x - 0.6, y: tip.y - 0.6, width: 1.2, height: 1.2))
        }
        return drawn
    }
}

/// A filled shape in design space that blots in, slightly off-register like
/// the site's mint prints.
struct DrawnFill: Shape {
    let path: Path
    let design: CGSize
    var progress: CGFloat
    var start: CGFloat = 0
    var length: CGFloat = 0.12

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let local = sketchStep(progress, start: start, length: length)
        guard local > 0 else { return Path() }
        let transform = DesignSpace.transform(design, into: rect)
        let fitted = path.applying(transform)
        let bounds = fitted.boundingRect
        let scale = 0.6 + 0.4 * local
        let grow = CGAffineTransform(translationX: bounds.midX, y: bounds.midY)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -bounds.midX, y: -bounds.midY)
        return fitted.applying(grow)
    }
}

/// Maps a fixed design canvas into a view's rect, centered, keeping its aspect.
enum DesignSpace {
    static func transform(_ design: CGSize, into rect: CGRect) -> CGAffineTransform {
        let scale = min(rect.width / design.width, rect.height / design.height)
        let x = rect.minX + (rect.width - design.width * scale) / 2
        let y = rect.minY + (rect.height - design.height * scale) / 2
        return CGAffineTransform(translationX: x, y: y).scaledBy(x: scale, y: scale)
    }

    static func point(_ point: CGPoint, design: CGSize, in size: CGSize) -> CGPoint {
        point.applying(transform(design, into: CGRect(origin: .zero, size: size)))
    }

    static func scale(_ design: CGSize, in size: CGSize) -> CGFloat {
        min(size.width / design.width, size.height / design.height)
    }
}

/// Reveals text left to right, as if it's being written, between `start` and `start + length`.
struct HandwritingReveal: ViewModifier, Animatable {
    var progress: CGFloat
    var start: CGFloat
    var length: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let local = min(1, max(0, (progress - start) / max(length, 0.001)))
        content
            .mask(alignment: .leading) {
                GeometryReader { proxy in
                    Rectangle().frame(width: proxy.size.width * local)
                }
            }
    }
}

/// Pops a view in with a little overshoot once the drawing reaches `start`.
struct StampIn: ViewModifier, Animatable {
    var progress: CGFloat
    var start: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let local = min(1, max(0, (progress - start) / 0.06))
        let overshoot = local < 1 ? 1.6 - 0.6 * local : 1
        content
            .scaleEffect(overshoot)
            .opacity(Double(local))
    }
}

extension View {
    func handwritten(_ progress: CGFloat, start: CGFloat, length: CGFloat = 0.12) -> some View {
        modifier(HandwritingReveal(progress: progress, start: start, length: length))
    }

    func stamped(_ progress: CGFloat, at start: CGFloat) -> some View {
        modifier(StampIn(progress: progress, start: start))
    }
}

/// Runs a drawing from blank to finished each time `key` changes. Respects
/// Reduce Motion by showing the finished drawing straight away.
struct DrawingClock: ViewModifier {
    @Binding var progress: CGFloat
    var duration: Double
    var key: AnyHashable
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.task(id: key) {
            progress = 0
            guard !reduceMotion else {
                progress = 1
                return
            }
            // One frame at zero so SwiftUI animates from blank.
            try? await Task.sleep(for: .milliseconds(30))
            withAnimation(.linear(duration: duration)) { progress = 1 }
        }
    }
}

extension View {
    func drawing(_ progress: Binding<CGFloat>, duration: Double, key: AnyHashable = 0) -> some View {
        modifier(DrawingClock(progress: progress, duration: duration, key: key))
    }
}

// MARK: - Paper

/// Fine grain over the warm page color, like the site's paper texture.
struct PaperBackground: View {
    var body: some View {
        Theme.background
            .overlay {
                Canvas { context, size in
                    var random = SketchRandom(seed: 42)
                    let count = Int(size.width * size.height / 260)
                    for _ in 0..<count {
                        let x = (random.next() + 1) / 2 * size.width
                        let y = (random.next() + 1) / 2 * size.height
                        let r = 0.4 + (random.next() + 1) * 0.35
                        context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)), with: .color(Theme.ink.opacity(0.07)))
                    }
                }
                .allowsHitTesting(false)
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

// MARK: - Stamps and receipts

/// A tilted rubber stamp, like the site's "memories kept" stamp.
struct RubberStamp: View {
    let top: String
    let main: String
    var color: Color = Theme.accent
    var angle: Double = -9

    var body: some View {
        VStack(spacing: 1) {
            Text(top.uppercased())
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.6)
            Text(main.uppercased())
                .font(.system(size: 21, weight: .black))
                .tracking(-0.3)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Theme.surface.opacity(0.85), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(color, lineWidth: 3))
        .rotationEffect(.degrees(angle))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(top) \(main)")
    }
}

/// A receipt with a rounded top and a torn zigzag bottom edge.
struct ReceiptShape: Shape {
    var tooth: CGFloat = 13

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r: CGFloat = 18
        let bottom = rect.maxY - tooth / 2
        path.move(to: CGPoint(x: rect.minX, y: bottom))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: bottom))
        let teeth = max(1, Int(rect.width / tooth))
        let step = rect.width / CGFloat(teeth)
        for i in 0..<teeth {
            let x = rect.maxX - step * CGFloat(i)
            path.addLine(to: CGPoint(x: x - step / 2, y: rect.maxY))
            path.addLine(to: CGPoint(x: x - step, y: bottom))
        }
        path.closeSubpath()
        return path
    }
}

/// A dashed rule across a receipt.
struct DashedRule: View {
    var body: some View {
        Rectangle()
            .stroke(Theme.ink.opacity(0.25), style: StrokeStyle(lineWidth: 2, dash: [5, 5]))
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

extension View {
    /// Sits the content on a torn receipt with a mint card peeking out behind it.
    func onReceipt(padding: CGFloat = 20) -> some View {
        self
            .padding(.horizontal, padding)
            .padding(.top, padding + 4)
            .padding(.bottom, padding + 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ReceiptShape().fill(Theme.surface))
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Theme.mint)
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.ink, lineWidth: 2))
                    .padding(.bottom, 22)
                    .rotationEffect(.degrees(1.4))
                    .offset(x: 9, y: 10)
            )
            .compositingGroup()
            .shadow(color: Theme.ink.opacity(0.14), radius: 14, y: 10)
    }
}

/// A round tick that draws itself in when it turns on. Used for picking items.
struct InkCheck: View {
    let isOn: Bool
    var size: CGFloat = 26
    var tint: Color = Theme.mint
    @State private var progress: CGFloat = 0

    private static let design = CGSize(width: 30, height: 30)

    var body: some View {
        ZStack {
            Circle()
                .fill(isOn ? tint : Theme.surface)
            DrawnStroke(path: Sketch.box(CGRect(x: 3, y: 3, width: 24, height: 24), radius: 12, wobble: 0.6, seed: 11), design: Self.design, progress: 1, showsPenTip: false)
                .stroke(Theme.ink, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            DrawnStroke(path: Sketch.check(in: CGRect(x: 8.5, y: 10, width: 13, height: 10)), design: Self.design, progress: progress, length: 1, showsPenTip: false)
                .stroke(Color(hex: 0x1A1A17), style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .onAppear { progress = isOn ? 1 : 0 }
        .onChange(of: isOn) { _, on in
            withAnimation(on ? .easeOut(duration: 0.28) : .easeIn(duration: 0.12)) { progress = on ? 1 : 0 }
        }
        .accessibilityHidden(true)
    }
}
