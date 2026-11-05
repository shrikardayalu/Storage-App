import Foundation

/// Build Plan step 9: spot "my phone keeps filling up", suggest a restart,
/// and measure what came back on the next open. Pure value logic; the app
/// supplies readings, the time since the phone started, and where it's saved.

/// Why Home is suggesting a look at storage.
public enum StorageWarning: Equatable, Sendable {
    /// Free space is very low.
    case low(availableBytes: Int64)
    /// Free space dropped a lot over the last few days.
    case shrinking(lostBytes: Int64, days: Int)

    /// Under this much free space, or under `lowFraction` of the phone, counts as low.
    public static let lowBytes: Int64 = 5_000_000_000
    public static let lowFraction = 0.05
    /// Losing this much free space within `shrinkWindowDays` counts as shrinking fast.
    public static let shrinkBytes: Int64 = 3_000_000_000
    public static let shrinkWindowDays = 3

    /// The warning for the latest reading and the saved history, or nil when storage looks fine.
    public static func evaluate(latest: StorageSnapshot?, history: StorageHistory) -> StorageWarning? {
        guard let latest else { return nil }
        let threshold = min(lowBytes, Int64(Double(latest.advertisedCapacityBytes) * lowFraction))
        if latest.availableBytes < max(threshold, 1_000_000_000) {
            return .low(availableBytes: latest.availableBytes)
        }
        let window = TimeInterval(shrinkWindowDays) * 86_400
        if let change = history.change(over: window), change <= -shrinkBytes {
            return .shrinking(lostBytes: -change, days: shrinkWindowDays)
        }
        return nil
    }
}

/// A restart the person said they're about to do: free space right before it.
public struct PendingRestart: Codable, Equatable, Sendable {
    public let baseline: StorageSnapshot

    public init(baseline: StorageSnapshot) {
        self.baseline = baseline
    }

    /// After this long without a restart, the suggestion is dropped: the
    /// baseline is too old to say what the restart itself gave back.
    public static let expiry: TimeInterval = 3 * 86_400

    /// Clock changes and rounding are allowed this much slack.
    public static let tolerance: TimeInterval = 60

    /// Whether the phone started up after the baseline was taken.
    /// - Parameter uptime: time since the phone started, including time asleep.
    public func restarted(now: Date, uptime: TimeInterval) -> Bool {
        let sinceBaseline = now.timeIntervalSince(baseline.date)
        return sinceBaseline > 0 && uptime + Self.tolerance < sinceBaseline
    }

    public func isExpired(now: Date) -> Bool {
        now.timeIntervalSince(baseline.date) > Self.expiry
    }

    /// Free space gained since the baseline; 0 if it went down.
    public func gained(now snapshot: StorageSnapshot) -> Int64 {
        max(0, snapshot.availableBytes - baseline.availableBytes)
    }
}

/// What a restart gave back, shown on Home until it's dismissed.
public struct RestartResult: Codable, Equatable, Sendable {
    public let date: Date
    public let gainedBytes: Int64

    public init(date: Date, gainedBytes: Int64) {
        self.date = date
        self.gainedBytes = gainedBytes
    }

    /// Below `FreedLedger.noiseFloor`, free space just moved on its own.
    public var gaveSpaceBack: Bool { gainedBytes >= FreedLedger.noiseFloor }
}

/// The restart coach's saved state.
public struct RestartCoachState: Codable, Equatable, Sendable {
    public var pending: PendingRestart?
    public var result: RestartResult?

    public init(pending: PendingRestart? = nil, result: RestartResult? = nil) {
        self.pending = pending
        self.result = result
    }
}
