import Foundation

/// Reads how much space the device has. Read-only.
///
/// The real implementation lives in the app target, because it reads volume
/// resource values that only Apple platforms report. StorageCore stays
/// Foundation-only so its tests run on Linux.
public protocol DeviceStorageService: Sendable {
    func currentSnapshot() async throws -> StorageSnapshot
}

/// Returns fixed numbers, for tests, previews, and screenshots.
public struct MockDeviceStorageService: DeviceStorageService {
    public var totalBytes: Int64
    public var availableBytes: Int64
    public var purgeableBytes: Int64
    /// Supplies each snapshot's date. Defaults to now.
    public var now: @Sendable () -> Date

    public init(
        totalBytes: Int64 = 119_000_000_000,
        availableBytes: Int64 = 23_400_000_000,
        purgeableBytes: Int64 = 3_100_000_000,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.totalBytes = totalBytes
        self.availableBytes = availableBytes
        self.purgeableBytes = purgeableBytes
        self.now = now
    }

    public func currentSnapshot() async throws -> StorageSnapshot {
        StorageSnapshot(
            date: now(),
            totalBytes: totalBytes,
            availableBytes: availableBytes,
            availableForImportantUsageBytes: availableBytes + purgeableBytes
        )
    }
}
