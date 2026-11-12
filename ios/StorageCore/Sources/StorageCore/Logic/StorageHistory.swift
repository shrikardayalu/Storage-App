import Foundation

/// Past storage readings, oldest first. Pure value logic; the app decides
/// where it's saved.
public struct StorageHistory: Codable, Equatable, Sendable {
    /// Readings closer together than this are treated as the same reading.
    public static let minimumInterval: TimeInterval = 60
    /// The oldest readings are dropped past this count.
    public static let maximumCount = 500

    public private(set) var snapshots: [StorageSnapshot]

    public init(snapshots: [StorageSnapshot] = []) {
        let sorted = snapshots.sorted { $0.date < $1.date }
        self.snapshots = Array(sorted.suffix(Self.maximumCount))
    }

    public var latest: StorageSnapshot? { snapshots.last }

    /// Adds `snapshot` unless the latest reading is under a minute older.
    /// Returns whether it was added.
    @discardableResult
    public mutating func append(_ snapshot: StorageSnapshot) -> Bool {
        if let latest, snapshot.date.timeIntervalSince(latest.date) < Self.minimumInterval {
            return false
        }
        snapshots.append(snapshot)
        if snapshots.count > Self.maximumCount {
            snapshots.removeFirst(snapshots.count - Self.maximumCount)
        }
        return true
    }

    /// Change in plain free space from the reading at the start of `window`
    /// (counting back from the latest reading) to the latest one. Negative means
    /// free space shrank. Nil when no reading is at least `window` old, or when
    /// the nearest earlier reading is itself much older than `window` (so the
    /// change would describe weeks as "3 days").
    public func change(over window: TimeInterval) -> Int64? {
        guard let latest else { return nil }
        let start = latest.date.addingTimeInterval(-window)
        // The newest reading taken at or before the start of the window.
        guard let baseline = snapshots.last(where: { $0.date <= start }) else { return nil }
        // The baseline has to sit inside the window, not years before it.
        guard start.timeIntervalSince(baseline.date) <= window else { return nil }
        return latest.availableBytes - baseline.availableBytes
    }
}
