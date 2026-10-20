import StorageCore
import SwiftUI

/// A placeholder thumbnail drawn from the item's seed: a flat little scene for
/// photos and videos, a sketch of an app screen for screenshots. Drawn with
/// `Canvas`, so thousands of cells cost no image decoding or network access.
struct MediaThumbnail: View {
    let item: MediaItem

    var body: some View {
        Canvas { context, size in
            let seed = item.thumbnailSeed
            switch item.category {
            case .screenshot:
                ThumbnailArt.drawScreen(in: &context, size: size, seed: seed)
            case .photo, .video:
                ThumbnailArt.drawScene(in: &context, size: size, seed: seed)
            }
        }
        .accessibilityHidden(true)
    }
}

enum ThumbnailArt {
    /// Muted sky / ground pairs that sit well next to the mint-and-ink UI.
    private static let palettes: [(sky: Color, far: Color, near: Color, sun: Color)] = [
        (Color(hex: 0xCFE6F0), Color(hex: 0x8FC1AE), Color(hex: 0x4E8F73), Color(hex: 0xFFF4D6)),
        (Color(hex: 0xF6DCC4), Color(hex: 0xD99F7C), Color(hex: 0x9B5E48), Color(hex: 0xFFF7EA)),
        (Color(hex: 0xDCD6EE), Color(hex: 0xA59AC9), Color(hex: 0x5F5592), Color(hex: 0xFDF1D2)),
        (Color(hex: 0xD7EEDF), Color(hex: 0x86C9A1), Color(hex: 0x2F7D57), Color(hex: 0xFFFBE8)),
        (Color(hex: 0xF3E7C9), Color(hex: 0xC9B27A), Color(hex: 0x7C6A3C), Color(hex: 0xFFFFFF)),
        (Color(hex: 0x2E3A4F), Color(hex: 0x4D5D78), Color(hex: 0x1E2636), Color(hex: 0xF4E9C1)),
        (Color(hex: 0xC9E4EA), Color(hex: 0x6FA8B6), Color(hex: 0x2F6675), Color(hex: 0xFFF2CF)),
    ]

    private static let ink = Color(hex: 0x1A1A17)

    static func drawScene(in context: inout GraphicsContext, size: CGSize, seed: UInt32) {
        var rng = SeededGenerator(seed: UInt64(seed))
        let palette = palettes[Int(seed % UInt32(palettes.count))]
        let w = size.width, h = size.height
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(palette.sky))

        // Sun or moon.
        let sunR = w * CGFloat.random(in: 0.08...0.13, using: &rng)
        let sun = CGPoint(x: w * CGFloat.random(in: 0.2...0.8, using: &rng), y: h * CGFloat.random(in: 0.18...0.35, using: &rng))
        context.fill(Path(ellipseIn: CGRect(x: sun.x - sunR, y: sun.y - sunR, width: sunR * 2, height: sunR * 2)), with: .color(palette.sun))

        // Two rolling hill layers.
        for (layer, color) in [(0, palette.far), (1, palette.near)] {
            let base = h * (layer == 0 ? 0.62 : 0.78)
            var path = Path()
            path.move(to: CGPoint(x: 0, y: h))
            path.addLine(to: CGPoint(x: 0, y: base))
            let bumps = Int.random(in: 2...3, using: &rng)
            for i in 0..<bumps {
                let x0 = w * CGFloat(i) / CGFloat(bumps)
                let x1 = w * CGFloat(i + 1) / CGFloat(bumps)
                let peak = base - h * CGFloat.random(in: 0.08...0.24, using: &rng)
                path.addQuadCurve(to: CGPoint(x: x1, y: base + CGFloat.random(in: -4...4, using: &rng)), control: CGPoint(x: (x0 + x1) / 2, y: peak))
            }
            path.addLine(to: CGPoint(x: w, y: h))
            path.closeSubpath()
            context.fill(path, with: .color(color))
        }

        // A few ink speckles for the printed feel.
        for _ in 0..<3 {
            let p = CGPoint(x: w * CGFloat.random(in: 0.05...0.95, using: &rng), y: h * CGFloat.random(in: 0.05...0.5, using: &rng))
            context.fill(Path(ellipseIn: CGRect(x: p.x, y: p.y, width: 1.6, height: 1.6)), with: .color(ink.opacity(0.35)))
        }
    }

    static func drawScreen(in context: inout GraphicsContext, size: CGSize, seed: UInt32) {
        var rng = SeededGenerator(seed: UInt64(seed))
        let w = size.width, h = size.height
        let dark = seed % 4 == 0
        let background = dark ? Color(hex: 0x1F1F1D) : Color(hex: 0xFBFAF6)
        let line = dark ? Color(hex: 0x4A4A45) : Color(hex: 0xDDD8CC)
        let accent = palettes[Int(seed % UInt32(palettes.count))].far
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(background))

        // Status / navigation bar.
        context.fill(Path(roundedRect: CGRect(x: w * 0.1, y: h * 0.08, width: w * 0.45, height: h * 0.06), cornerRadius: 2), with: .color(line))

        var y = h * 0.22
        let layout = Int.random(in: 0..<3, using: &rng)
        if layout == 0 {
            // Chat bubbles.
            while y < h * 0.9 {
                let left = Bool.random(using: &rng)
                let bw = w * CGFloat.random(in: 0.35...0.6, using: &rng)
                let rect = CGRect(x: left ? w * 0.08 : w * 0.92 - bw, y: y, width: bw, height: h * 0.07)
                context.fill(Path(roundedRect: rect, cornerRadius: rect.height / 2), with: .color(left ? line : accent))
                y += h * 0.11
            }
        } else {
            // Image block followed by text lines (article, receipt, or map card).
            let blockHeight = h * (layout == 1 ? 0.3 : 0.18)
            context.fill(Path(roundedRect: CGRect(x: w * 0.08, y: y, width: w * 0.84, height: blockHeight), cornerRadius: 4), with: .color(accent))
            y += blockHeight + h * 0.06
            while y < h * 0.9 {
                let lw = w * CGFloat.random(in: 0.45...0.84, using: &rng)
                context.fill(Path(roundedRect: CGRect(x: w * 0.08, y: y, width: lw, height: h * 0.035), cornerRadius: 2), with: .color(line))
                y += h * 0.075
            }
        }
    }
}

#Preview {
    let items = Array(MockMediaFactory.makeLibrary(for: .typical).prefix(24))
    return ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 2)], spacing: 2) {
            ForEach(items) { item in
                MediaThumbnail(item: item).aspectRatio(1, contentMode: .fit)
            }
        }
    }
}
