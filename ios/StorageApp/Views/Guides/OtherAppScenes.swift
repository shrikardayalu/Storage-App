import SwiftUI

/// Drawings for the other-app guides, built from two pieces: a home screen
/// with one app circled, and a phone showing a Settings-style list with one
/// row circled. Same design space and pen timing as `GuideScenes`.
enum OtherAppScenes {
    private static let phone = CGRect(x: 88, y: 8, width: 124, height: 272)

    /// What sits at the right end of a row.
    enum Accessory {
        case none
        case chevron
        case check
        case toggle(on: Bool)
        /// A size or short word, like "2.1 GB" or "Enable".
        case text(String, Color = Theme.ink)
        /// The row is swiped left, showing a red Delete.
        case swipeDelete
    }

    struct Row {
        var text: String
        var accessory: Accessory = .chevron
        var color: Color = Theme.ink

        init(_ text: String, _ accessory: Accessory = .chevron, color: Color = Theme.ink) {
            self.text = text
            self.accessory = accessory
            self.color = color
        }
    }

    private static func phoneFrame(seed: UInt64) -> [SceneMark] {
        [
            .stroke(Sketch.box(phone, radius: 22, wobble: 1.3, seed: seed), 0, 0.22, width: 2.8),
            .stroke(Sketch.box(CGRect(x: 133, y: 18, width: 34, height: 9), radius: 4.5, wobble: 0.4, seed: seed + 1), 0.2, 0.05, width: 2),
        ]
    }

    /// A label whose left edge sits at `x`. Handwriting is centered, so this
    /// guesses its width from the longest line.
    private static func leftLabel(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat, start: CGFloat, color: Color) -> SceneMark {
        let longest = text.split(separator: "\n").map(\.count).max() ?? 0
        return .label(text, at: CGPoint(x: x + CGFloat(longest) * size * 0.24, y: y), start, size: size, color: color)
    }

    // MARK: Home screen

    /// A home screen with one app's icon filled in and circled.
    static func homeScreen(app: String, color: Color, note: String, seed: UInt64) -> [SceneMark] {
        var marks = phoneFrame(seed: seed)
        let target = CGRect(x: 137, y: 136, width: 26, height: 26)
        var next = seed + 10
        for row in 0..<4 {
            for col in 0..<3 {
                let rect = CGRect(x: 103 + CGFloat(col) * 34, y: 48 + CGFloat(row) * 44, width: 26, height: 26)
                let isTarget = rect.origin == target.origin
                let start = 0.25 + CGFloat(row * 3 + col) * 0.022
                if isTarget {
                    marks.append(.fill(Sketch.box(rect, radius: 7, seed: next), 0.56, color: color))
                }
                marks.append(.stroke(Sketch.box(rect, radius: 7, wobble: 0.7, seed: next), start, 0.05, width: isTarget ? 2.4 : 1.6))
                next += 1
            }
        }
        marks += [
            .label(app, at: CGPoint(x: target.midX, y: target.maxY + 9), 0.62, size: 9),
            .stroke(Sketch.loop(around: target.insetBy(dx: -12, dy: -12), seed: seed + 30), 0.68, 0.14, color: Theme.tomato, width: 3),
            .stroke(Sketch.arrow(from: CGPoint(x: 262, y: 70), to: CGPoint(x: 182, y: 140), bend: -26, seed: seed + 31), 0.8, 0.1, width: 2.4),
            .label(note, at: CGPoint(x: 150, y: 302), 0.88, size: 16, angle: -2, color: Theme.accent),
        ]
        return marks
    }

    // MARK: A list screen

    /// A phone showing a titled list, with the row at `target` circled and a
    /// handwritten note underneath.
    static func list(_ header: String, rows: [Row], target: Int?, note: String, noteColor: Color = Theme.accent, seed: UInt64) -> [SceneMark] {
        var marks = phoneFrame(seed: seed)
        marks.append(.label(header, at: CGPoint(x: 150, y: 46), 0.24, size: 12))
        marks.append(.stroke(Sketch.line(CGPoint(x: 98, y: 60), CGPoint(x: 202, y: 60), wobble: 0.5, seed: seed + 2), 0.27, 0.04, color: Theme.ink.opacity(0.35), width: 1))

        let rowHeight: CGFloat = 32
        for (index, row) in rows.enumerated() {
            let top = 64 + CGFloat(index) * rowHeight
            let mid = top + rowHeight / 2
            let start = 0.32 + CGFloat(index) * 0.06
            let rowSeed = seed + 10 + UInt64(index) * 7
            let isTarget = index == target
            let textColor = isTarget && row.color == Theme.ink ? Theme.tomato : row.color
            let size: CGFloat = row.text.contains("\n") ? 8 : 9.5
            var textX: CGFloat = 100

            switch row.accessory {
            case .none:
                break
            case .chevron:
                marks.append(.stroke(Sketch.curve([CGPoint(x: 194, y: mid - 4), CGPoint(x: 198, y: mid), CGPoint(x: 194, y: mid + 4)], wobble: 0.3, seed: rowSeed), start + 0.03, 0.02, color: Theme.ink.opacity(0.5), width: 1.4))
            case .check:
                marks.append(.stroke(Sketch.check(in: CGRect(x: 186, y: mid - 4, width: 11, height: 8), seed: rowSeed), start + 0.04, 0.04, color: Theme.accent, width: 2.2))
            case .toggle(let on):
                let track = CGRect(x: 178, y: mid - 6, width: 22, height: 12)
                if on { marks.append(.fill(Sketch.box(track, radius: 6, wobble: 0.3, seed: rowSeed), start + 0.03, color: Theme.mint)) }
                marks.append(.stroke(Sketch.box(track, radius: 6, wobble: 0.3, seed: rowSeed + 1), start + 0.03, 0.03, width: 1.4))
                let knob = CGRect(x: on ? 189 : 179, y: mid - 5, width: 10, height: 10)
                marks.append(.fill(Path(ellipseIn: knob), start + 0.05, color: Theme.surface))
                marks.append(.stroke(Sketch.loop(around: knob, turns: 1.02, seed: rowSeed + 2), start + 0.05, 0.02, width: 1.2))
            case .text(let text, let color):
                marks.append(.label(text, at: CGPoint(x: 200 - CGFloat(text.count) * 2.1, y: mid), start + 0.03, size: 8, color: color))
            case .swipeDelete:
                // The row slides left to show Delete.
                textX = 96
                let button = CGRect(x: 168, y: top + 3, width: 36, height: rowHeight - 6)
                marks.append(.fill(Sketch.box(button, radius: 4, wobble: 0.4, seed: rowSeed), start + 0.08, color: Theme.tomato))
                marks.append(.label("Delete", at: CGPoint(x: button.midX, y: mid), start + 0.1, size: 8.5, color: .white))
                marks.append(.stroke(Sketch.arrow(from: CGPoint(x: 160, y: mid + 18), to: CGPoint(x: 118, y: mid + 18), bend: 4, seed: rowSeed + 3), start + 0.14, 0.06, color: Theme.ink.opacity(0.6), width: 1.6))
            }
            marks.append(leftLabel(row.text, x: textX, y: mid, size: size, start: start, color: textColor))
            marks.append(.stroke(Sketch.line(CGPoint(x: 98, y: top + rowHeight), CGPoint(x: 202, y: top + rowHeight), wobble: 0.4, seed: rowSeed + 4), start + 0.02, 0.03, color: Theme.ink.opacity(0.25), width: 1))
            if isTarget {
                marks.append(.stroke(Sketch.loop(around: CGRect(x: 94, y: top + 2, width: 112, height: rowHeight - 4), seed: rowSeed + 5), 0.72, 0.13, color: Theme.tomato, width: 3))
                marks.append(.stroke(Sketch.arrow(from: CGPoint(x: 266, y: max(40, mid - 60)), to: CGPoint(x: 214, y: mid - 4), bend: -18, seed: rowSeed + 6), 0.84, 0.08, width: 2.4))
            }
        }
        marks.append(.label(note, at: CGPoint(x: 150, y: 302), 0.9, size: 16, angle: -2, color: noteColor))
        return marks
    }
}
