import Foundation

/// Item count and storage for one slice of the library.
public struct CategoryTotal: Hashable, Sendable {
    public var count: Int
    public var bytes: Int64

    public init(count: Int = 0, bytes: Int64 = 0) {
        self.count = count
        self.bytes = bytes
    }

    public static let zero = CategoryTotal()
}

/// Storage figures for the whole library, derived from its items.
/// Every number on the Home screen comes from here.
public struct LibrarySummary: Hashable, Sendable {
    /// Videos at or above this size count as "large videos".
    public static let largeVideoThreshold: Int64 = 100 * 1_000_000

    public var total: CategoryTotal
    public var byCategory: [MediaCategory: CategoryTotal]
    public var largeVideos: CategoryTotal
    /// Storage freed if every screenshot were deleted.
    public var screenshotBytes: Int64
    /// Storage freed by compressing every eligible photo and video at the balanced level.
    public var compressionSavings: Int64

    /// Screenshots are suggested for deletion; photos and videos for compression.
    public var potentialSavings: Int64 { screenshotBytes + compressionSavings }

    public subscript(category: MediaCategory) -> CategoryTotal {
        byCategory[category] ?? .zero
    }

    public init(items: [MediaItem]) {
        var total = CategoryTotal()
        var byCategory: [MediaCategory: CategoryTotal] = [:]
        var largeVideos = CategoryTotal()
        var compressionSavings: Int64 = 0

        for item in items {
            total.count += 1
            total.bytes += item.currentBytes
            byCategory[item.category, default: .zero].count += 1
            byCategory[item.category, default: .zero].bytes += item.currentBytes

            if item.category == .video, item.currentBytes >= Self.largeVideoThreshold {
                largeVideos.count += 1
                largeVideos.bytes += item.currentBytes
            }
            if item.category != .screenshot {
                compressionSavings += CompressionModel.estimate(for: item, level: .balanced).savedBytes
            }
        }

        self.total = total
        self.byCategory = byCategory
        self.largeVideos = largeVideos
        self.screenshotBytes = byCategory[.screenshot]?.bytes ?? 0
        self.compressionSavings = compressionSavings
    }

    public static let empty = LibrarySummary(items: [])
}

/// Running totals of what simulated cleanup has recovered since the last reset.
public struct SessionSavings: Hashable, Sendable {
    public var deletedCount: Int = 0
    public var deletedBytes: Int64 = 0
    public var compressedCount: Int = 0
    public var compressedBytes: Int64 = 0

    public init() {}

    public var totalBytes: Int64 { deletedBytes + compressedBytes }
    public var isEmpty: Bool { totalBytes == 0 && deletedCount == 0 && compressedCount == 0 }
}
