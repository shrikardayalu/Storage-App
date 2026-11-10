import StorageCore
import SwiftUI
import UIKit

/// The person's choice of light or dark, kept across launches. `system` follows
/// the iPhone's own setting; the other two override it for this app only.
enum AppearanceSetting: String, CaseIterable, Identifiable {
    case system, light, dark

    static let storageKey = "appearanceSetting"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// `nil` hands control back to the iPhone's setting.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Colors, type, and shared styles. Clean system UI first, with a few
/// hand-printed touches: ink outlines, mint fills, and offset "sticker" shadows.
enum Theme {
    // MARK: Colors

    /// Warm off-white page background (near-black in dark mode).
    static let background = dynamic(light: 0xF4F1EA, dark: 0x121211)
    /// Card surfaces.
    static let surface = dynamic(light: 0xFFFDF8, dark: 0x1D1D1B)
    /// Recessed surfaces such as thumbnail placeholders and progress tracks.
    static let well = dynamic(light: 0xEBE6DA, dark: 0x2A2A27)
    /// Illustration ink: outlines and sticker shadows.
    static let ink = dynamic(light: 0x1A1A17, dark: 0xEFEADF)
    /// Brand mint, used for fills behind ink-colored content.
    static let mint = Color(hex: 0x5ED49B)
    /// Pale mint for secondary fills.
    static let mintSoft = dynamic(light: 0xCDEFDC, dark: 0x24493A)
    /// Accent for text and controls; darker than `mint` so it reads on light backgrounds.
    static let accent = dynamic(light: 0x1C7D50, dark: 0x6FE0A8)
    /// Destructive actions.
    static let tomato = dynamic(light: 0xEF6A4C, dark: 0xF07B5E)
    static let hairline = dynamic(light: 0x1A1A17, dark: 0xEFEADF, alpha: 0.09)
    /// Light fills inside illustrations; matches the illustration generator's "paper".
    static let illustrationPaper = dynamic(light: 0xFBF8F1, dark: 0x23231F)
    /// Darker mint for illustration shading; the generator's "shade".
    static let illustrationShade = dynamic(light: 0x3DAE77, dark: 0x2F9563)

    static func color(for category: MediaCategory) -> Color {
        switch category {
        case .photo: mint
        case .video: ink
        case .screenshot: dynamic(light: 0xA9DDC2, dark: 0x3E7A5C)
        }
    }

    // MARK: Metrics

    static let cardRadius: CGFloat = 22
    static let spacing: CGFloat = 16

    private static func dynamic(light: UInt32, dark: UInt32, alpha: CGFloat = 1) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light, alpha: alpha)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(uiColor: UIColor(hex: hex))
    }
}

// MARK: - Cards

struct CardBackground: ViewModifier {
    var padding: CGFloat = Theme.spacing

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
    }
}

/// A card with an ink outline and a hard offset shadow, like a printed sticker.
/// Used sparingly, for the one thing on a screen that matters most.
struct StickerBackground: ViewModifier {
    var fill: Color = Theme.surface
    var radius: CGFloat = Theme.cardRadius
    var padding: CGFloat = Theme.spacing

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(Theme.ink, lineWidth: 1.75))
            .background(shape.fill(Theme.ink).offset(x: -3, y: 4))
    }
}

extension View {
    func card(padding: CGFloat = Theme.spacing) -> some View {
        modifier(CardBackground(padding: padding))
    }

    func sticker(fill: Color = Theme.surface, radius: CGFloat = Theme.cardRadius, padding: CGFloat = Theme.spacing) -> some View {
        modifier(StickerBackground(fill: fill, radius: radius, padding: padding))
    }
}

// MARK: - Buttons

/// Mint, ink-outlined button with a sticker shadow that presses flat.
struct StickerButtonStyle: ButtonStyle {
    var fill: Color = Theme.mint
    var foreground: Color = Color(hex: 0x1A1A17)

    func makeBody(configuration: Configuration) -> some View {
        StickerButtonBody(configuration: configuration, fill: fill, foreground: foreground)
    }

    private struct StickerButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let fill: Color
        let foreground: Color
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
            let pressed = configuration.isPressed
            configuration.label
                .font(.headline)
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity, minHeight: 52)
                .padding(.horizontal, 16)
                .background(shape.fill(isEnabled ? fill : Theme.well))
                .overlay(shape.strokeBorder(Color(hex: 0x1A1A17), lineWidth: 1.75))
                .background(shape.fill(Theme.ink).offset(x: pressed ? 0 : -3, y: pressed ? 0 : 4))
                .offset(x: pressed ? -3 : 0, y: pressed ? 4 : 0)
                .opacity(isEnabled ? 1 : 0.55)
                .animation(.snappy(duration: 0.12), value: pressed)
        }
    }
}

/// Quiet secondary button: tinted text on a soft surface.
struct SoftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Theme.mintSoft.opacity(configuration.isPressed ? 0.6 : 1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

extension ButtonStyle where Self == StickerButtonStyle {
    static var sticker: StickerButtonStyle { StickerButtonStyle() }
    static var stickerDestructive: StickerButtonStyle { StickerButtonStyle(fill: Theme.tomato) }
}

extension ButtonStyle where Self == SoftButtonStyle {
    static var soft: SoftButtonStyle { SoftButtonStyle() }
}

// MARK: - Typography

extension Font {
    /// Rounded, heavy numerals for storage figures.
    static func metric(_ style: Font.TextStyle) -> Font {
        .system(style, design: .rounded).weight(.bold)
    }
}

/// A storage size with the number large and the unit smaller, e.g. "4.2 GB".
struct SizeText: View {
    let bytes: Int64
    var style: Font.TextStyle = .largeTitle
    var unitStyle: Font.TextStyle = .title3
    var precision: ByteFormatter.Precision = .compact

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(ByteFormatter.value(bytes, precision: precision))
                .font(.metric(style))
                .monospacedDigit()
            Text(ByteFormatter.unitLabel(bytes, precision: precision))
                .font(.system(unitStyle, design: .rounded).weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ByteFormatter.accessibilityString(bytes, precision: precision))
    }
}
