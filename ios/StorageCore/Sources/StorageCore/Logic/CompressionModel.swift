import Foundation

/// How aggressively simulated compression shrinks a file.
public enum CompressionLevel: String, CaseIterable, Codable, Hashable, Sendable, Comparable, Identifiable {
    case light
    case balanced
    case maximum

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .light: "Light"
        case .balanced: "Balanced"
        case .maximum: "Maximum"
        }
    }

    public var detail: String {
        switch self {
        case .light: "Barely noticeable difference"
        case .balanced: "Good quality, much smaller"
        case .maximum: "Smallest files, visible softening"
        }
    }

    private var rank: Int {
        switch self {
        case .light: 0
        case .balanced: 1
        case .maximum: 2
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }
}

/// Why an item cannot be compressed by the simulated model.
public enum CompressionIneligibility: Hashable, Sendable {
    /// The format is never compressed (for example ProRAW or ProRes, which people keep for editing).
    case unsupportedFormat(MediaFormat)
    /// The item is already at or below what this level would produce.
    case alreadyOptimized
    /// The file is too small for compression to matter.
    case tooSmall

    public var explanation: String {
        switch self {
        case .unsupportedFormat(let format):
            "\(format.displayName) files are kept at full quality for editing, so they aren't compressed."
        case .alreadyOptimized:
            "Already compressed to this level or smaller."
        case .tooSmall:
            "Too small to benefit from compression."
        }
    }

    public var shortLabel: String {
        switch self {
        case .unsupportedFormat(let format): "\(format.displayName) not supported"
        case .alreadyOptimized: "Already compressed"
        case .tooSmall: "Too small"
        }
    }
}

/// The predicted result of compressing a single item.
public enum CompressionEstimate: Hashable, Sendable {
    case compressible(newBytes: Int64, savedBytes: Int64)
    case ineligible(CompressionIneligibility)

    public var savedBytes: Int64 {
        if case .compressible(_, let saved) = self { return saved }
        return 0
    }
}

/// A plausible, deterministic model of how much space compression would save.
///
/// Nothing here touches real files. Ratios are applied to an item's *original*
/// size, so re-compressing at a stronger level shrinks further, while repeating
/// the same level reports `alreadyOptimized`.
public enum CompressionModel {
    /// Files smaller than this are left alone.
    public static let minimumBytes: Int64 = 200_000
    /// A result must save at least this fraction of the current size to count.
    static let minimumGainFraction = 0.03

    /// Output size as a fraction of the original size.
    public static func ratio(for category: MediaCategory, level: CompressionLevel) -> Double {
        switch (category, level) {
        case (.video, .light): 0.70
        case (.video, .balanced): 0.45
        case (.video, .maximum): 0.28
        case (.photo, .light): 0.82
        case (.photo, .balanced): 0.62
        case (.photo, .maximum): 0.45
        // Screenshots are mostly flat PNGs, which re-encode very efficiently.
        case (.screenshot, .light): 0.55
        case (.screenshot, .balanced): 0.35
        case (.screenshot, .maximum): 0.22
        }
    }

    /// Reasons that hold regardless of compression level.
    public static func unsupportedReason(for item: MediaItem) -> CompressionIneligibility? {
        switch item.format {
        case .proRAW, .proRes:
            return .unsupportedFormat(item.format)
        default:
            return item.originalBytes < minimumBytes ? .tooSmall : nil
        }
    }

    public static func estimate(for item: MediaItem, level: CompressionLevel) -> CompressionEstimate {
        if let reason = unsupportedReason(for: item) {
            return .ineligible(reason)
        }
        let target = Int64((Double(item.originalBytes) * ratio(for: item.category, level: level)).rounded())
        let saved = item.currentBytes - target
        guard saved > Int64(Double(item.currentBytes) * minimumGainFraction) else {
            return .ineligible(.alreadyOptimized)
        }
        return .compressible(newBytes: target, savedBytes: saved)
    }
}

/// The predicted outcome of compressing a group of items at one level.
public struct CompressionPlan: Hashable, Sendable {
    public struct Skipped: Hashable, Sendable {
        public let reason: CompressionIneligibility
        public let count: Int
        public let bytes: Int64
    }

    public let level: CompressionLevel
    public let eligibleCount: Int
    public let bytesBefore: Int64
    public let bytesAfter: Int64
    /// Ineligible items grouped by reason, largest group first.
    public let skipped: [Skipped]

    public var savedBytes: Int64 { bytesBefore - bytesAfter }
    public var skippedCount: Int { skipped.reduce(0) { $0 + $1.count } }
    public var hasWork: Bool { eligibleCount > 0 }

    public init(items: [MediaItem], level: CompressionLevel) {
        var eligible = 0
        var before: Int64 = 0
        var after: Int64 = 0
        var skippedByReason: [CompressionIneligibility: (count: Int, bytes: Int64)] = [:]

        for item in items {
            switch CompressionModel.estimate(for: item, level: level) {
            case .compressible(let newBytes, _):
                eligible += 1
                before += item.currentBytes
                after += newBytes
            case .ineligible(let reason):
                skippedByReason[reason, default: (0, 0)].count += 1
                skippedByReason[reason, default: (0, 0)].bytes += item.currentBytes
            }
        }

        self.level = level
        self.eligibleCount = eligible
        self.bytesBefore = before
        self.bytesAfter = after
        self.skipped = skippedByReason
            .map { Skipped(reason: $0.key, count: $0.value.count, bytes: $0.value.bytes) }
            .sorted { ($0.count, $0.reason.shortLabel) > ($1.count, $1.reason.shortLabel) }
    }
}
