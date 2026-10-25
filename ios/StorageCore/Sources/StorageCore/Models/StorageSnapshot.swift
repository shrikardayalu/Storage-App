import Foundation

/// One reading of the phone's storage, taken from the volume that holds the
/// app's home directory. Read-only: taking a snapshot changes nothing.
public struct StorageSnapshot: Codable, Equatable, Hashable, Sendable {
    public let date: Date
    /// Capacity of the volume. Below the advertised size, as in Settings.
    public let totalBytes: Int64
    /// Plain free space right now.
    public let availableBytes: Int64
    /// Free space plus what iOS could purge (caches, offloadable data) if asked.
    public let availableForImportantUsageBytes: Int64

    public init(date: Date, totalBytes: Int64, availableBytes: Int64, availableForImportantUsageBytes: Int64) {
        self.date = date
        self.totalBytes = totalBytes
        self.availableBytes = availableBytes
        self.availableForImportantUsageBytes = availableForImportantUsageBytes
    }

    public var usedBytes: Int64 {
        max(0, totalBytes - availableBytes)
    }

    /// The size printed on the box (64, 128, 256 GB…), which is what Settings
    /// shows as capacity. The volume itself reports less, because iOS keeps
    /// part of the disk for its own system volumes.
    public var advertisedCapacityBytes: Int64 {
        Self.advertisedCapacity(forVolumeBytes: totalBytes)
    }

    /// The smallest standard iPhone capacity (decimal GB, a power of two)
    /// that holds `volumeBytes`.
    public static func advertisedCapacity(forVolumeBytes volumeBytes: Int64) -> Int64 {
        var size: Int64 = 16_000_000_000
        while size < volumeBytes {
            size *= 2
        }
        return size
    }

    /// Space iOS could reclaim on its own. Stored for the storage-health step;
    /// not shown to people yet.
    public var purgeableEstimateBytes: Int64 {
        max(0, availableForImportantUsageBytes - availableBytes)
    }

    /// Share of the advertised capacity in use, from 0 to 1, matching the bar in Settings.
    public var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, Double(usedBytes) / Double(advertisedCapacityBytes))
    }
}
