import Foundation

/// The single place storage sizes are turned into text.
///
/// Uses decimal units (1 KB = 1,000 bytes), matching how iOS reports storage in
/// Settings. Implemented by hand rather than with `ByteCountFormatter` so output
/// is identical on every platform the tests run on.
public enum ByteFormatter {
    public enum Unit: String, CaseIterable, Sendable {
        case bytes
        case kb = "KB"
        case mb = "MB"
        case gb = "GB"
        case tb = "TB"

        var divisor: Double {
            switch self {
            case .bytes: 1
            case .kb: 1e3
            case .mb: 1e6
            case .gb: 1e9
            case .tb: 1e12
            }
        }

        var next: Unit? {
            let all = Unit.allCases
            let index = all.firstIndex(of: self)!
            return index + 1 < all.count ? all[index + 1] : nil
        }

        var spokenName: String {
            switch self {
            case .bytes: "bytes"
            case .kb: "kilobytes"
            case .mb: "megabytes"
            case .gb: "gigabytes"
            case .tb: "terabytes"
            }
        }
    }

    /// How many decimals to show.
    public enum Precision: Sendable {
        /// One decimal below 10 ("4.2 GB"), none from 10 up ("512 MB").
        case compact
        /// Always two decimals, as Settings shows device storage ("125.11 GB").
        case twoDecimals
    }

    /// The number and unit that `string(_:)` would show.
    public static func components(_ bytes: Int64, precision: Precision = .compact) -> (value: String, unit: Unit) {
        let magnitude = Double(bytes.magnitude)
        var unit: Unit = switch magnitude {
        case ..<1e3: .bytes
        case ..<1e6: .kb
        case ..<1e9: .mb
        case ..<1e12: .gb
        default: .tb
        }
        if unit == .bytes { return (String(bytes), .bytes) }

        var scaled = Double(bytes) / unit.divisor
        var decimals = switch precision {
        case .compact: abs(scaled) < 9.95 ? 1 : 0
        case .twoDecimals: 2
        }
        // 999,700 bytes would round to "1000 KB"; show "1.0 MB" instead.
        let factor = pow(10, Double(decimals))
        if abs((scaled * factor).rounded() / factor) >= 1000, let next = unit.next {
            unit = next
            scaled = Double(bytes) / unit.divisor
            decimals = precision == .compact ? 1 : 2
        }
        return (String(format: "%.\(decimals)f", scaled), unit)
    }

    /// Numeric part only, e.g. "1.4" for 1,400,000,000 bytes.
    public static func value(_ bytes: Int64, precision: Precision = .compact) -> String {
        components(bytes, precision: precision).value
    }

    /// Unit label only, e.g. "GB". Consistent with `value(_:)`.
    public static func unitLabel(_ bytes: Int64, precision: Precision = .compact) -> String {
        let unit = components(bytes, precision: precision).unit
        if unit == .bytes { return bytes == 1 ? "byte" : "bytes" }
        return unit.rawValue
    }

    /// Full string, e.g. "1.4 GB", "512 MB", "0 bytes".
    public static func string(_ bytes: Int64, precision: Precision = .compact) -> String {
        "\(value(bytes, precision: precision)) \(unitLabel(bytes, precision: precision))"
    }

    /// Spoken form for VoiceOver, e.g. "1.4 gigabytes".
    public static func accessibilityString(_ bytes: Int64, precision: Precision = .compact) -> String {
        let (value, unit) = components(bytes, precision: precision)
        return "\(value) \(unit.spokenName)"
    }
}

/// Formats video durations as "0:42" or "1:02:05".
public enum DurationFormatter {
    public static func string(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
