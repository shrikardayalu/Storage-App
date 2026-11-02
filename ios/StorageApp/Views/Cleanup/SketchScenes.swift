import SwiftUI

/// One stroke, fill, or handwritten label in a scene, with when it's drawn.
/// Times are shares of the scene's whole drawing, from 0 to 1.
struct SceneMark {
    enum Kind {
        case stroke(Path, width: CGFloat)
        case fill(Path)
        case label(String, at: CGPoint, size: CGFloat, angle: Double)
    }

    var kind: Kind
    var start: CGFloat
    var length: CGFloat
    var color: Color

    static func stroke(_ path: Path, _ start: CGFloat, _ length: CGFloat, color: Color = Theme.ink, width: CGFloat = 2.4) -> SceneMark {
        SceneMark(kind: .stroke(path, width: width), start: start, length: length, color: color)
    }

    static func fill(_ path: Path, _ start: CGFloat, color: Color = Theme.mint) -> SceneMark {
        SceneMark(kind: .fill(path), start: start, length: 0.08, color: color)
    }

    static func label(_ text: String, at point: CGPoint, _ start: CGFloat, size: CGFloat = 13, angle: Double = 0, color: Color = Theme.ink) -> SceneMark {
        SceneMark(kind: .label(text, at: point, size: size, angle: angle), start: start, length: 0.1, color: color)
    }
}

/// Draws a list of marks in a fixed design space as `progress` runs from 0 to 1.
struct SketchCanvas: View {
    static let design = CGSize(width: 300, height: 320)

    let marks: [SceneMark]
    let progress: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let scale = DesignSpace.scale(Self.design, in: proxy.size)
            ZStack(alignment: .topLeading) {
                ForEach(marks.indices, id: \.self) { index in
                    mark(marks[index], scale: scale, size: proxy.size)
                }
            }
        }
        .aspectRatio(Self.design, contentMode: .fit)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func mark(_ mark: SceneMark, scale: CGFloat, size: CGSize) -> some View {
        switch mark.kind {
        case .stroke(let path, let width):
            DrawnStroke(path: path, design: Self.design, progress: progress, start: mark.start, length: mark.length)
                .stroke(mark.color, style: StrokeStyle(lineWidth: width * scale, lineCap: .round, lineJoin: .round))
        case .fill(let path):
            // Printed a touch off-register, like the site's mint fills.
            DrawnFill(path: path, design: Self.design, progress: progress, start: mark.start, length: mark.length)
                .fill(mark.color)
                .offset(x: -2.5 * scale, y: 2.5 * scale)
        case .label(let text, let point, let fontSize, let angle):
            Text(text)
                .font(.hand(fontSize * scale))
                .foregroundStyle(mark.color)
                .fixedSize()
                .handwritten(progress, start: mark.start, length: mark.length)
                .rotationEffect(.degrees(angle))
                .position(DesignSpace.point(point, design: Self.design, in: size))
        }
    }
}

/// The drawings for each step of the Recently Deleted guide.
enum GuideScenes {
    private static let phone = CGRect(x: 88, y: 8, width: 124, height: 272)

    /// The phone outline and its island, drawn first in most scenes.
    private static func phoneFrame(seed: UInt64) -> [SceneMark] {
        [
            .stroke(Sketch.box(phone, radius: 22, wobble: 1.3, seed: seed), 0, 0.22, width: 2.8),
            .stroke(Sketch.box(CGRect(x: 133, y: 18, width: 34, height: 9), radius: 4.5, wobble: 0.4, seed: seed + 1), 0.2, 0.05, width: 2),
        ]
    }

    // MARK: Why

    /// A bin of photos with a "30 days" tag: deleted photos still take space.
    static let waiting: [SceneMark] = {
        let bin = CGRect(x: 108, y: 128, width: 84, height: 118)
        return [
            .fill(Sketch.box(CGRect(x: 116, y: 86, width: 42, height: 34), radius: 5, seed: 30), 0.02),
            .stroke(Sketch.box(CGRect(x: 116, y: 86, width: 42, height: 34), radius: 5, seed: 31), 0.02, 0.1),
            .fill(Sketch.box(CGRect(x: 144, y: 78, width: 42, height: 34), radius: 5, seed: 32), 0.1),
            .stroke(Sketch.box(CGRect(x: 144, y: 78, width: 42, height: 34), radius: 5, seed: 33), 0.1, 0.1),
            .stroke(Sketch.curve([CGPoint(x: 150, y: 104), CGPoint(x: 160, y: 94), CGPoint(x: 168, y: 101), CGPoint(x: 180, y: 90)], seed: 34), 0.18, 0.06, width: 1.8),
            .stroke(Sketch.box(bin, radius: 8, seed: 35), 0.24, 0.2, width: 2.8),
            .stroke(Sketch.line(CGPoint(x: 98, y: 124), CGPoint(x: 202, y: 124), seed: 36), 0.42, 0.08, width: 3),
            .stroke(Sketch.box(CGRect(x: 134, y: 110, width: 32, height: 14), radius: 5, seed: 37), 0.48, 0.06),
            .stroke(Sketch.line(CGPoint(x: 132, y: 146), CGPoint(x: 134, y: 230), seed: 38), 0.54, 0.05, width: 2),
            .stroke(Sketch.line(CGPoint(x: 150, y: 146), CGPoint(x: 150, y: 230), seed: 39), 0.58, 0.05, width: 2),
            .stroke(Sketch.line(CGPoint(x: 168, y: 146), CGPoint(x: 166, y: 230), seed: 40), 0.62, 0.05, width: 2),
            .stroke(Sketch.curve([CGPoint(x: 192, y: 150), CGPoint(x: 210, y: 158), CGPoint(x: 222, y: 172)], seed: 41), 0.68, 0.05, width: 1.8),
            .fill(Sketch.box(CGRect(x: 208, y: 172, width: 74, height: 34), radius: 6, seed: 42), 0.72, color: Theme.mintSoft),
            .stroke(Sketch.box(CGRect(x: 208, y: 172, width: 74, height: 34), radius: 6, seed: 43), 0.72, 0.08),
            .label("30 days", at: CGPoint(x: 245, y: 189), 0.8, size: 15),
            .label("still using space!", at: CGPoint(x: 92, y: 284), 0.84, size: 17, angle: -4, color: Theme.tomato),
            .stroke(Sketch.scribble(width: 120, at: CGPoint(x: 34, y: 300), seed: 44), 0.92, 0.08, color: Theme.tomato, width: 3),
        ]
    }()

    // MARK: Why, after a Live Photo conversion

    /// The still stays in the album; only the old Live version is in the bin.
    static let stillsKept: [SceneMark] = {
        let still = CGRect(x: 22, y: 70, width: 100, height: 128)
        let live = CGRect(x: 192, y: 64, width: 70, height: 88)
        let bin = CGRect(x: 172, y: 124, width: 110, height: 116)
        return [
            // Left: the still, kept.
            .fill(Sketch.box(still, radius: 10, seed: 500), 0.02, color: Theme.mintSoft),
            .stroke(Sketch.box(still, radius: 10, seed: 501), 0.02, 0.14, width: 2.8),
            .stroke(Sketch.curve([CGPoint(x: 34, y: 172), CGPoint(x: 56, y: 146), CGPoint(x: 76, y: 162), CGPoint(x: 110, y: 130)], seed: 502), 0.14, 0.06, width: 2),
            .stroke(Sketch.loop(around: CGRect(x: 92, y: 84, width: 16, height: 16), turns: 1.02, seed: 503), 0.18, 0.04, width: 1.8),
            .fill(Path(ellipseIn: CGRect(x: 92, y: 42, width: 44, height: 44)), 0.24, color: Theme.mint),
            .stroke(Sketch.loop(around: CGRect(x: 94, y: 44, width: 40, height: 40), turns: 1.05, seed: 504), 0.24, 0.06, width: 2.4),
            .stroke(Sketch.check(in: CGRect(x: 104, y: 56, width: 20, height: 15), seed: 505), 0.3, 0.05, width: 3.2),
            .label("your still", at: CGPoint(x: 72, y: 218), 0.36, size: 17),
            .label("stays in your album", at: CGPoint(x: 72, y: 240), 0.42, size: 14, color: Theme.accent),
            .stroke(Sketch.scribble(width: 110, at: CGPoint(x: 18, y: 254), seed: 506), 0.48, 0.06, color: Theme.mint, width: 3.2),

            // Divider.
            .stroke(Sketch.line(CGPoint(x: 150, y: 50), CGPoint(x: 152, y: 270), wobble: 1.5, seed: 507), 0.52, 0.06, color: Theme.ink.opacity(0.3), width: 1.6),

            // Right: the Live version, with its video, in the bin.
            .fill(Sketch.box(live, radius: 8, seed: 510), 0.58, color: Theme.surface),
            .stroke(Sketch.box(live, radius: 8, seed: 511), 0.58, 0.1, width: 2.2),
            .stroke(Sketch.loop(around: CGRect(x: 202, y: 74, width: 12, height: 12), turns: 1.02, seed: 512), 0.66, 0.03, width: 1.6),
            .stroke(Sketch.loop(around: CGRect(x: 197, y: 69, width: 22, height: 22), turns: 1.02, seed: 513), 0.68, 0.03, width: 1.4),
            .label("LIVE", at: CGPoint(x: 236, y: 80), 0.7, size: 10),
            .stroke(Sketch.box(bin, radius: 8, seed: 514), 0.72, 0.1, width: 2.8),
            .stroke(Sketch.line(CGPoint(x: 164, y: 120), CGPoint(x: 290, y: 120), seed: 515), 0.8, 0.04, width: 3),
            .stroke(Sketch.line(CGPoint(x: 202, y: 150), CGPoint(x: 204, y: 226), seed: 516), 0.83, 0.03, width: 1.8),
            .stroke(Sketch.line(CGPoint(x: 227, y: 150), CGPoint(x: 227, y: 226), seed: 517), 0.85, 0.03, width: 1.8),
            .stroke(Sketch.line(CGPoint(x: 252, y: 150), CGPoint(x: 250, y: 226), seed: 518), 0.87, 0.03, width: 1.8),
            .label("old Live version", at: CGPoint(x: 227, y: 262), 0.9, size: 15, color: Theme.tomato),
            .label("(photo + 3 sec video)", at: CGPoint(x: 227, y: 282), 0.94, size: 12, color: Theme.tomato),
        ]
    }()

    // MARK: Open Photos

    /// A home screen with the Photos icon circled.
    static let openPhotos: [SceneMark] = {
        var marks = phoneFrame(seed: 50)
        var seed: UInt64 = 60
        let photosIcon = CGRect(x: 137, y: 92, width: 26, height: 26)
        for row in 0..<4 {
            for col in 0..<3 {
                let rect = CGRect(x: 103 + CGFloat(col) * 34, y: 48 + CGFloat(row) * 44, width: 26, height: 26)
                let isPhotos = rect.origin == photosIcon.origin
                let start = 0.25 + CGFloat(row * 3 + col) * 0.022
                if isPhotos {
                    marks.append(.fill(Sketch.box(rect, radius: 7, seed: seed), start, color: Theme.surface))
                }
                marks.append(.stroke(Sketch.box(rect, radius: 7, wobble: 0.7, seed: seed), start, 0.05, width: isPhotos ? 2.4 : 1.6))
                seed += 1
            }
        }
        // The Photos flower: six petals.
        let center = CGPoint(x: photosIcon.midX, y: photosIcon.midY)
        let petalColors: [Color] = [Theme.mint, Theme.tomato, Theme.mint, Color(hex: 0xF5C451), Theme.mint, Color(hex: 0x7BA7E8)]
        for i in 0..<6 {
            let angle = Double(i) / 6 * 2 * .pi
            let petal = CGRect(x: center.x + CGFloat(cos(angle)) * 5 - 4, y: center.y + CGFloat(sin(angle)) * 5 - 4, width: 8, height: 8)
            marks.append(.fill(Path(ellipseIn: petal), 0.56 + CGFloat(i) * 0.015, color: petalColors[i].opacity(0.85)))
        }
        marks += [
            .label("Photos", at: CGPoint(x: 150, y: 127), 0.62, size: 9),
            .stroke(Sketch.loop(around: photosIcon.insetBy(dx: -12, dy: -12), seed: 70), 0.68, 0.14, color: Theme.tomato, width: 3),
            .stroke(Sketch.arrow(from: CGPoint(x: 262, y: 50), to: CGPoint(x: 182, y: 96), bend: -26, seed: 71), 0.8, 0.1, width: 2.4),
            .label("tap Photos", at: CGPoint(x: 252, y: 32), 0.88, size: 16, angle: 6),
        ]
        return marks
    }()

    // MARK: Find Recently Deleted

    /// The Photos app scrolled down to Utilities, with Recently Deleted circled.
    static let findAlbum: [SceneMark] = {
        var marks = phoneFrame(seed: 80)
        var seed: UInt64 = 90
        // A strip of photos at the top that's scrolling away.
        for col in 0..<3 {
            let rect = CGRect(x: 100 + CGFloat(col) * 34, y: 40, width: 30, height: 30)
            marks.append(.fill(Sketch.box(rect, radius: 3, seed: seed), 0.25 + CGFloat(col) * 0.03, color: Theme.mintSoft))
            marks.append(.stroke(Sketch.box(rect, radius: 3, wobble: 0.6, seed: seed + 50), 0.25 + CGFloat(col) * 0.03, 0.04, width: 1.4))
            seed += 1
        }
        marks.append(.label("Utilities", at: CGPoint(x: 127, y: 96), 0.38, size: 13))
        let rows = ["Imports", "Hidden", "Duplicates", "Recently Deleted"]
        for (i, title) in rows.enumerated() {
            let y = 122 + CGFloat(i) * 34
            let start = 0.44 + CGFloat(i) * 0.06
            let isTarget = i == rows.count - 1
            marks.append(.stroke(Sketch.box(CGRect(x: 102, y: y - 8, width: 16, height: 16), radius: 4, wobble: 0.5, seed: seed), start, 0.04, color: isTarget ? Theme.tomato : Theme.ink, width: 1.6))
            marks.append(.label(title, at: CGPoint(x: 124 + CGFloat(title.count) * 2.6, y: y), start + 0.02, size: isTarget ? 11 : 10, color: isTarget ? Theme.tomato : Theme.ink))
            marks.append(.stroke(Sketch.line(CGPoint(x: 102, y: y + 15), CGPoint(x: 200, y: y + 15), wobble: 0.5, seed: seed + 7), start + 0.03, 0.03, color: Theme.ink.opacity(0.35), width: 1))
            seed += 1
        }
        marks += [
            .stroke(Sketch.loop(around: CGRect(x: 96, y: 210, width: 116, height: 24), seed: 99), 0.7, 0.13, color: Theme.tomato, width: 3),
            .stroke(Sketch.arrow(from: CGPoint(x: 240, y: 52), to: CGPoint(x: 240, y: 210), bend: 14, seed: 100), 0.32, 0.14, width: 2.4),
            .label("scroll down", at: CGPoint(x: 264, y: 130), 0.42, size: 14, angle: 82),
            .label("Face ID unlocks it", at: CGPoint(x: 150, y: 300), 0.86, size: 16, angle: -3, color: Theme.accent),
        ]
        return marks
    }()

    // MARK: Select and delete

    /// Recently Deleted with a few photos picked, Select and Delete marked.
    static let select: [SceneMark] = {
        var marks = phoneFrame(seed: 110)
        marks += [
            .label("Recently Deleted", at: CGPoint(x: 133, y: 44), 0.24, size: 9),
            .label("Select", at: CGPoint(x: 191, y: 44), 0.28, size: 10, color: Theme.accent),
            .stroke(Sketch.loop(around: CGRect(x: 176, y: 34, width: 30, height: 20), seed: 111), 0.34, 0.08, color: Theme.tomato, width: 2.6),
        ]
        var seed: UInt64 = 120
        let picked: Set<Int> = [0, 1, 3]
        for i in 0..<9 {
            let rect = CGRect(x: 99 + CGFloat(i % 3) * 35, y: 62 + CGFloat(i / 3) * 35, width: 32, height: 32)
            let start = 0.4 + CGFloat(i) * 0.018
            marks.append(.fill(Sketch.box(rect, radius: 3, seed: seed), start, color: picked.contains(i) ? Theme.mint.opacity(0.7) : Theme.mintSoft))
            marks.append(.stroke(Sketch.box(rect, radius: 3, wobble: 0.6, seed: seed + 40), start, 0.04, width: 1.4))
            if picked.contains(i) {
                marks.append(.stroke(Sketch.check(in: CGRect(x: rect.maxX - 13, y: rect.maxY - 12, width: 9, height: 7), seed: seed), 0.6 + CGFloat(i) * 0.03, 0.04, width: 2.2))
            }
            seed += 1
        }
        marks += [
            .label("Delete", at: CGPoint(x: 116, y: 262), 0.74, size: 12, color: Theme.tomato),
            .stroke(Sketch.scribble(width: 38, at: CGPoint(x: 97, y: 272), seed: 130), 0.8, 0.06, color: Theme.tomato, width: 2.4),
            .stroke(Sketch.arrow(from: CGPoint(x: 60, y: 210), to: CGPoint(x: 96, y: 254), bend: 18, seed: 131), 0.84, 0.07, width: 2.2),
            .label("just the ones", at: CGPoint(x: 46, y: 176), 0.88, size: 14, angle: -6),
            .label("you deleted", at: CGPoint(x: 48, y: 194), 0.92, size: 14, angle: -6),
        ]
        return marks
    }()

    // MARK: Confirm

    /// iOS's own sheet, with Delete From This iPhone circled.
    static let confirm: [SceneMark] = {
        var marks = phoneFrame(seed: 140)
        var seed: UInt64 = 150
        for i in 0..<6 {
            let rect = CGRect(x: 99 + CGFloat(i % 3) * 35, y: 46 + CGFloat(i / 3) * 35, width: 32, height: 32)
            marks.append(.stroke(Sketch.box(rect, radius: 3, wobble: 0.6, seed: seed), 0.24 + CGFloat(i) * 0.015, 0.03, color: Theme.ink.opacity(0.35), width: 1.2))
            seed += 1
        }
        let sheet = CGRect(x: 96, y: 186, width: 108, height: 84)
        marks += [
            .fill(Sketch.box(sheet, radius: 12, seed: 160), 0.36, color: Theme.surface),
            .stroke(Sketch.box(sheet, radius: 12, seed: 161), 0.36, 0.12, width: 2.2),
            .label("These items will be", at: CGPoint(x: 150, y: 202), 0.48, size: 8, color: Theme.ink.opacity(0.7)),
            .label("deleted for good", at: CGPoint(x: 150, y: 213), 0.5, size: 8, color: Theme.ink.opacity(0.7)),
            .stroke(Sketch.line(CGPoint(x: 100, y: 226), CGPoint(x: 200, y: 226), wobble: 0.4, seed: 162), 0.52, 0.03, color: Theme.ink.opacity(0.3), width: 1),
            .label("Delete From This iPhone", at: CGPoint(x: 150, y: 242), 0.56, size: 9.5, color: Theme.tomato),
            .label("Cancel", at: CGPoint(x: 150, y: 260), 0.6, size: 9, color: Theme.accent),
            .stroke(Sketch.loop(around: CGRect(x: 96, y: 230, width: 108, height: 24), seed: 163), 0.66, 0.13, color: Theme.tomato, width: 3),
            .stroke(Sketch.line(CGPoint(x: 214, y: 220), CGPoint(x: 228, y: 210), seed: 164), 0.82, 0.03, width: 2.6),
            .stroke(Sketch.line(CGPoint(x: 218, y: 240), CGPoint(x: 236, y: 240), seed: 165), 0.85, 0.03, width: 2.6),
            .stroke(Sketch.line(CGPoint(x: 214, y: 258), CGPoint(x: 228, y: 268), seed: 166), 0.88, 0.03, width: 2.6),
            .label("this is what frees it", at: CGPoint(x: 150, y: 302), 0.9, size: 16, angle: -2, color: Theme.accent),
        ]
        return marks
    }()

    // MARK: Live Photo → still

    /// Three stacked frames with the Live rings becoming one still.
    static let liveToStill: [SceneMark] = {
        var marks: [SceneMark] = []
        for i in 0..<3 {
            let rect = CGRect(x: 26 + CGFloat(i) * 10, y: 96 - CGFloat(i) * 10, width: 92, height: 120)
            marks.append(.fill(Sketch.box(rect, radius: 8, seed: UInt64(200 + i)), CGFloat(i) * 0.08, color: i == 2 ? Theme.mintSoft : Theme.surface))
            marks.append(.stroke(Sketch.box(rect, radius: 8, seed: UInt64(210 + i)), CGFloat(i) * 0.08, 0.12, width: 2.2))
        }
        let rings = CGPoint(x: 70, y: 104)
        marks += [
            .stroke(Sketch.loop(around: CGRect(x: rings.x - 6, y: rings.y - 6, width: 12, height: 12), turns: 1.02, seed: 220), 0.3, 0.05, width: 1.8),
            .stroke(Sketch.loop(around: CGRect(x: rings.x - 12, y: rings.y - 12, width: 24, height: 24), turns: 1.02, seed: 221), 0.34, 0.05, width: 1.6),
            .label("LIVE", at: CGPoint(x: 104, y: 104), 0.38, size: 11),
            .stroke(Sketch.curve([CGPoint(x: 62, y: 170), CGPoint(x: 80, y: 150), CGPoint(x: 96, y: 162), CGPoint(x: 116, y: 140)], seed: 222), 0.4, 0.06, width: 1.8),
            .label("+3 sec of video", at: CGPoint(x: 80, y: 250), 0.46, size: 14, angle: -4, color: Theme.tomato),
            .stroke(Sketch.arrow(from: CGPoint(x: 140, y: 150), to: CGPoint(x: 182, y: 150), bend: -12, seed: 223), 0.55, 0.1, width: 2.6),
            .fill(Sketch.box(CGRect(x: 192, y: 90, width: 92, height: 120), radius: 8, seed: 224), 0.66, color: Theme.mintSoft),
            .stroke(Sketch.box(CGRect(x: 192, y: 90, width: 92, height: 120), radius: 8, seed: 225), 0.66, 0.14, width: 2.6),
            .stroke(Sketch.curve([CGPoint(x: 206, y: 176), CGPoint(x: 224, y: 156), CGPoint(x: 240, y: 168), CGPoint(x: 262, y: 144)], seed: 226), 0.8, 0.06, width: 1.8),
            .label("same photo", at: CGPoint(x: 238, y: 238), 0.86, size: 15, angle: 3, color: Theme.accent),
            .stroke(Sketch.scribble(width: 84, at: CGPoint(x: 196, y: 254), seed: 227), 0.92, 0.07, color: Theme.mint, width: 3.2),
        ]
        return marks
    }()

    // MARK: Burst → best shot

    /// A fanned burst with one shot circled to keep and the rest crossed out.
    static let burstPick: [SceneMark] = {
        var marks: [SceneMark] = []
        let keep = 2
        for i in 0..<5 {
            let rect = CGRect(x: 16 + CGFloat(i) * 54, y: 96 + CGFloat(i % 2) * 8, width: 50, height: 66)
            let t = CGFloat(i) * 0.07
            marks.append(.fill(Sketch.box(rect, radius: 6, seed: UInt64(600 + i)), t, color: i == keep ? Theme.mintSoft : Theme.surface))
            marks.append(.stroke(Sketch.box(rect, radius: 6, seed: UInt64(610 + i)), t, 0.1, width: i == keep ? 2.6 : 2))
            marks.append(.stroke(Sketch.curve([CGPoint(x: rect.minX + 8, y: rect.maxY - 12), CGPoint(x: rect.midX, y: rect.midY), CGPoint(x: rect.maxX - 8, y: rect.minY + 18)], seed: UInt64(620 + i)), t + 0.06, 0.04, width: 1.4))
            if i != keep {
                marks.append(.stroke(Sketch.line(CGPoint(x: rect.minX + 4, y: rect.minY + 4), CGPoint(x: rect.maxX - 4, y: rect.maxY - 4), seed: UInt64(630 + i)), 0.56 + CGFloat(i) * 0.04, 0.04, color: Theme.tomato, width: 2.2))
                marks.append(.stroke(Sketch.line(CGPoint(x: rect.maxX - 4, y: rect.minY + 4), CGPoint(x: rect.minX + 4, y: rect.maxY - 4), seed: UInt64(640 + i)), 0.58 + CGFloat(i) * 0.04, 0.04, color: Theme.tomato, width: 2.2))
            }
        }
        let kept = CGRect(x: 16 + CGFloat(keep) * 54, y: 96, width: 50, height: 66)
        marks += [
            .label("5 shots, 1 second", at: CGPoint(x: 150, y: 62), 0.36, size: 15, angle: -2),
            .stroke(Sketch.loop(around: kept.insetBy(dx: -10, dy: -10), turns: 1.12, seed: 650), 0.44, 0.1, color: Theme.accent, width: 2.8),
            .label("keep", at: CGPoint(x: kept.midX, y: 206), 0.78, size: 19, angle: 3, color: Theme.accent),
            .label("the rest go to Recently Deleted", at: CGPoint(x: 150, y: 252), 0.86, size: 14, color: Theme.tomato),
            .stroke(Sketch.scribble(width: 120, at: CGPoint(x: 90, y: 222), seed: 651), 0.92, 0.07, color: Theme.mint, width: 3.2),
        ]
        return marks
    }()
}
