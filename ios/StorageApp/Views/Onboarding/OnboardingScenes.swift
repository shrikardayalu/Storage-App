import SwiftUI

// Ink drawings for onboarding. They boil: every stroke is pushed through a
// gentle field that shifts with the boil clock (`Sketch.boil`), so lines
// shimmer like hand-drawn animation without changing shape.

/// Draws a list of marks in `design` space, boiling each pose.
struct InkScene: View {
    let design: CGSize
    let progress: CGFloat
    /// How far points move, in design units.
    var boil: CGFloat = 0.9
    let marks: () -> [SceneMark]

    var body: some View {
        let list = marks()
        BoilPoseReader { pose in
            GeometryReader { proxy in
                let scale = DesignSpace.scale(design, in: proxy.size)
                ZStack(alignment: .topLeading) {
                    ForEach(list.indices, id: \.self) { index in
                        mark(list[index], pose: pose, scale: scale, size: proxy.size)
                    }
                }
            }
        }
        .aspectRatio(design, contentMode: .fit)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func mark(_ mark: SceneMark, pose: Int, scale: CGFloat, size: CGSize) -> some View {
        switch mark.kind {
        case .stroke(let path, let width):
            DrawnStroke(path: Sketch.boil(path, pose: pose, amount: boil), design: design, progress: progress, start: mark.start, length: mark.length)
                .stroke(mark.color, style: StrokeStyle(lineWidth: width * scale, lineCap: .round, lineJoin: .round))
        case .fill(let path):
            DrawnFill(path: Sketch.boil(path, pose: pose, amount: boil), design: design, progress: progress, start: mark.start, length: mark.length)
                .fill(mark.color)
                .offset(x: -2.5 * scale, y: 2.5 * scale)
        case .label(let text, let point, let fontSize, let angle):
            Text(text)
                .font(.hand(fontSize * scale))
                .foregroundStyle(mark.color)
                .fixedSize()
                .handwritten(progress, start: mark.start, length: mark.length)
                .rotationEffect(.degrees(angle))
                .position(DesignSpace.point(point, design: design, in: size))
        }
    }
}

/// A small photo print: the frame is traced, the paper blots in, then the
/// hills and the sun. It takes `pace` of the scene's drawing, from `start`.
private func photoMarks(_ rect: CGRect, start: CGFloat, pace: CGFloat, seed: UInt64) -> [SceneMark] {
    let hills = Sketch.curve([
        CGPoint(x: rect.minX + 3, y: rect.maxY - 4),
        CGPoint(x: rect.minX + rect.width * 0.32, y: rect.minY + rect.height * 0.5),
        CGPoint(x: rect.minX + rect.width * 0.52, y: rect.minY + rect.height * 0.72),
        CGPoint(x: rect.minX + rect.width * 0.74, y: rect.minY + rect.height * 0.46),
        CGPoint(x: rect.maxX - 3, y: rect.maxY - 4),
    ], wobble: 0.7, seed: seed + 1)
    let sunSide = rect.width * 0.2
    let sun = CGRect(x: rect.maxX - sunSide - rect.width * 0.14, y: rect.minY + rect.height * 0.14, width: sunSide, height: sunSide)
    // Listed back to front; the times are what make it read as drawn.
    return [
        SceneMark(kind: .fill(Sketch.box(rect, radius: 4, wobble: 0.8, seed: seed)),
                  start: start + pace * 0.3, length: pace * 0.25, color: Theme.illustrationPaper),
        .stroke(Sketch.box(rect, radius: 4, wobble: 0.8, seed: seed + 2), start, pace * 0.5, width: 2),
        SceneMark(kind: .fill(Sketch.box(sun, radius: sunSide / 2, wobble: 0.4, seed: seed + 3)),
                  start: start + pace * 0.8, length: pace * 0.2, color: Theme.mint),
        .stroke(hills, start + pace * 0.45, pace * 0.4, width: 1.8),
    ]
}

// MARK: - The hero phone

/// The one drawing that stays on screen through all of onboarding, so the
/// steps read as one story: it fills up, spills over, gets a padlock, prints
/// the scan, and drains as the reveal counts up.
struct HeroPhone: View {
    /// Draws the outline in, 0 to 1. Only animated once, on the first screen.
    var drawProgress: CGFloat
    /// Tank fill, 0 to 1. Animate changes to see it rise or drain.
    var level: CGFloat
    /// Photos spilling over the top, 0 to 1. Animate it and they draw
    /// themselves on one by one; back to 0 and they're rubbed out again.
    var spill: CGFloat
    /// The padlock over the front, drawn on from 0 to 1.
    var lock: CGFloat
    var stamped: Bool

    static let design = CGSize(width: 220, height: 260)
    private static let phone = CGRect(x: 62, y: 14, width: 96, height: 232)
    private static let tank = CGRect(x: 74, y: 46, width: 72, height: 180)

    var body: some View {
        ZStack {
            TankLevel(level: level, tank: Self.tank, design: Self.design)
            InkScene(design: Self.design, progress: drawProgress, marks: Self.phoneMarks)
            InkScene(design: Self.design, progress: spill, marks: Self.spillMarks)
            InkScene(design: Self.design, progress: lock, marks: Self.lockMarks)
        }
        .aspectRatio(Self.design, contentMode: .fit)
        .overlay {
            GeometryReader { proxy in
                let scale = DesignSpace.scale(Self.design, in: proxy.size)
                RubberStamp(top: "storage", main: "almost full", color: Theme.tomato, angle: 11)
                    .scaleEffect(scale * 0.95 * (stamped ? 1 : 2.2))
                    .opacity(stamped ? 1 : 0)
                    .boilingShape(seed: 2)
                    .position(DesignSpace.point(CGPoint(x: 178, y: 36), design: Self.design, in: proxy.size))
            }
        }
        .accessibilityHidden(true)
    }

    private static func phoneMarks() -> [SceneMark] {
        var marks: [SceneMark] = [
            .fill(Sketch.box(phone, radius: 20, wobble: 1, seed: 299), 0, color: Theme.surface),
            .stroke(Sketch.box(phone, radius: 20, wobble: 1.3, seed: 300), 0, 0.3, width: 3),
            .stroke(Sketch.box(CGRect(x: phone.midX - 16, y: phone.minY + 10, width: 32, height: 9), radius: 4.5, wobble: 0.5, seed: 302), 0.25, 0.08, width: 2.2),
            .stroke(Sketch.box(tank, radius: 8, wobble: 0.9, seed: 304), 0.3, 0.2, width: 2.2),
        ]
        // Ticks up the side of the tank, like a measuring jug.
        for step in 1...4 {
            let y = tank.maxY - tank.height * CGFloat(step) / 5
            marks.append(.stroke(Sketch.line(CGPoint(x: tank.minX - 1, y: y), CGPoint(x: tank.minX + 9, y: y), wobble: 0.4, seed: 310 + UInt64(step)),
                                 0.45 + CGFloat(step) * 0.04, 0.06, width: 1.6))
        }
        return marks
    }

    /// Photos spilling over the top once the phone is nearly full.
    private static func spillMarks() -> [SceneMark] {
        let spill: [CGRect] = [
            CGRect(x: 22, y: 40, width: 40, height: 32),
            CGRect(x: 160, y: 66, width: 42, height: 33),
            CGRect(x: 92, y: 0, width: 36, height: 28),
            CGRect(x: 6, y: 112, width: 34, height: 27),
        ]
        var marks: [SceneMark] = []
        // One print after another, each still being finished as the next starts.
        for (index, rect) in spill.enumerated() {
            marks += photoMarks(rect, start: CGFloat(index) * 0.18, pace: 0.4, seed: 330 + UInt64(index) * 10)
        }
        // Then the little falling lines beside them.
        marks.append(.stroke(Sketch.curve([CGPoint(x: 18, y: 80), CGPoint(x: 12, y: 90), CGPoint(x: 12, y: 98)], wobble: 0.5, seed: 390), 0.8, 0.14, width: 1.6))
        marks.append(.stroke(Sketch.curve([CGPoint(x: 206, y: 104), CGPoint(x: 210, y: 112), CGPoint(x: 208, y: 120)], wobble: 0.5, seed: 392), 0.86, 0.14, width: 1.6))
        return marks
    }

    /// A padlock over the front of the phone.
    private static func lockMarks() -> [SceneMark] {
        let body = CGRect(x: 124, y: 176, width: 58, height: 46)
        let shackle = Sketch.curve([
            CGPoint(x: body.minX + 12, y: body.minY + 2),
            CGPoint(x: body.minX + 12, y: body.minY - 14),
            CGPoint(x: body.midX, y: body.minY - 27),
            CGPoint(x: body.maxX - 12, y: body.minY - 14),
            CGPoint(x: body.maxX - 12, y: body.minY + 2),
        ], wobble: 0.6, seed: 430)
        // Shackle, then the body's outline, its mint fill, and the keyhole last.
        return [
            .stroke(shackle, 0, 0.35, width: 4.4),
            SceneMark(kind: .fill(Sketch.box(body, radius: 9, wobble: 0.9, seed: 432)), start: 0.6, length: 0.2, color: Theme.mint),
            .stroke(Sketch.box(body, radius: 9, wobble: 1, seed: 433), 0.25, 0.5, width: 2.8),
            .stroke(Sketch.line(CGPoint(x: body.midX, y: body.midY - 7), CGPoint(x: body.midX, y: body.midY + 8), wobble: 0.3, seed: 435), 0.8, 0.2, width: 3.6),
        ]
    }
}

/// The tank's contents: mint up to 80%, tomato above it.
private struct TankLevel: View, Animatable {
    var level: CGFloat
    let tank: CGRect
    let design: CGSize

    var animatableData: CGFloat {
        get { level }
        set { level = newValue }
    }

    var body: some View {
        GeometryReader { proxy in
            let transform = DesignSpace.transform(design, into: CGRect(origin: .zero, size: proxy.size))
            let inner = tank.insetBy(dx: 3, dy: 3)
            let height = inner.height * min(max(level, 0), 1)
            let safe = min(height, inner.height * 0.8)
            ZStack {
                Path(CGRect(x: inner.minX, y: inner.maxY - safe, width: inner.width, height: safe))
                    .applying(transform)
                    .fill(Theme.mint)
                if height > safe {
                    Path(CGRect(x: inner.minX, y: inner.maxY - height, width: inner.width, height: height - safe))
                        .applying(transform)
                        .fill(Theme.tomato)
                }
            }
            .clipShape(Sketch.box(inner, radius: 6, wobble: 0, seed: 1).applying(transform))
        }
    }
}

// MARK: - Confetti

/// A one-off burst of inked squiggles, ticks and dots, fired when `trigger` changes.
struct InkConfetti: View {
    let trigger: Int
    @State private var burst: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Piece {
        let angle: Double
        let distance: CGFloat
        let spin: Double
        let color: Color
        let shape: Int
    }

    private static let pieces: [Piece] = {
        var random = SketchRandom(seed: 808)
        let colors = [Theme.mint, Theme.tomato, Theme.ink, Theme.illustrationShade]
        return (0..<26).map { index in
            Piece(
                angle: Double(index) / 26 * 2 * .pi + Double(random.next()) * 0.2,
                distance: 120 + random.next() * 50,
                spin: Double(random.next()) * 260,
                color: colors[index % colors.count],
                shape: index % 3
            )
        }
    }()

    var body: some View {
        ZStack {
            ForEach(Self.pieces.indices, id: \.self) { index in
                let piece = Self.pieces[index]
                PieceShape(kind: piece.shape, seed: UInt64(index))
                    .stroke(piece.color, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                    .frame(width: 18, height: 18)
                    .rotationEffect(.degrees(piece.spin * Double(burst)))
                    .offset(
                        x: CGFloat(cos(piece.angle)) * piece.distance * burst,
                        y: CGFloat(sin(piece.angle)) * piece.distance * burst + 90 * burst * burst
                    )
                    .opacity(burst == 0 ? 0 : Double(1 - burst * burst * burst))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) { _, _ in
            guard !reduceMotion else { return }
            burst = 0
            withAnimation(.easeOut(duration: 1.3)) { burst = 1 }
        }
    }

    private struct PieceShape: Shape {
        let kind: Int
        let seed: UInt64

        func path(in rect: CGRect) -> Path {
            switch kind {
            case 0:
                Sketch.curve([CGPoint(x: rect.minX, y: rect.midY), CGPoint(x: rect.width * 0.33, y: rect.minY), CGPoint(x: rect.width * 0.66, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.midY)], wobble: 0.6, seed: seed)
            case 1:
                Sketch.check(in: rect.insetBy(dx: 3, dy: 4), seed: seed)
            default:
                Sketch.box(rect.insetBy(dx: 5, dy: 5), radius: 4, wobble: 0.5, seed: seed)
            }
        }
    }
}
