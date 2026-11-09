import Foundation

/// Tracks the free space that comes back after a cleanup. Deleted photos sit in
/// Recently Deleted for 30 days, so the space returns only after the person
/// empties it; this compares free space then against the reading taken just
/// before the cleanup.
public struct ReclaimMeasurement: Hashable, Sendable {
    /// Free space right before anything was changed.
    public let baseline: StorageSnapshot
    /// What the cleanup should give back once Recently Deleted is emptied.
    public let expectedBytes: Int64
    /// The most recent reading since the cleanup, if any.
    public private(set) var latest: StorageSnapshot?

    /// At least this share of the expected bytes counts as "got it back". Free
    /// space moves on its own (caches, downloads), so exact matches are rare.
    public static let doneFraction = 0.6

    public init(baseline: StorageSnapshot, expectedBytes: Int64) {
        self.baseline = baseline
        self.expectedBytes = expectedBytes
    }

    public mutating func record(_ snapshot: StorageSnapshot) {
        guard snapshot.date >= baseline.date else { return }
        latest = snapshot
    }

    /// Free space gained since the baseline; never negative. Right after
    /// Recently Deleted is emptied, iOS often marks the space purgeable before
    /// it shows up as plain free space, so a gain in either reading counts.
    public var reclaimedBytes: Int64 {
        guard let latest else { return 0 }
        let plain = latest.availableBytes - baseline.availableBytes
        let important = latest.availableForImportantUsageBytes - baseline.availableForImportantUsageBytes
        return max(0, plain, important)
    }

    /// Progress toward the expected amount, from 0 to 1.
    public var fraction: Double {
        guard expectedBytes > 0 else { return reclaimedBytes > 0 ? 1 : 0 }
        return min(1, Double(reclaimedBytes) / Double(expectedBytes))
    }

    public var isDone: Bool {
        fraction >= Self.doneFraction
    }
}
