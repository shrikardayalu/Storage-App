import XCTest
@testable import StorageCore

final class StorageHistoryTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func snapshot(minutes: Double, free: Int64 = 20_000_000_000, important: Int64? = nil) -> StorageSnapshot {
        StorageSnapshot(
            date: start.addingTimeInterval(minutes * 60),
            totalBytes: 128_000_000_000,
            availableBytes: free,
            availableForImportantUsageBytes: important ?? free
        )
    }

    // MARK: Snapshot math

    func testUsedAndPurgeable() {
        let s = StorageSnapshot(date: start, totalBytes: 100, availableBytes: 30, availableForImportantUsageBytes: 45)
        XCTAssertEqual(s.usedBytes, 70)
        XCTAssertEqual(s.purgeableEstimateBytes, 15)
    }

    func testAdvertisedCapacityRoundsUpToStandardSize() {
        XCTAssertEqual(StorageSnapshot.advertisedCapacity(forVolumeBytes: 127_400_000_000), 128_000_000_000)
        XCTAssertEqual(StorageSnapshot.advertisedCapacity(forVolumeBytes: 119_261_339_648), 128_000_000_000)
        XCTAssertEqual(StorageSnapshot.advertisedCapacity(forVolumeBytes: 128_000_000_000), 128_000_000_000)
        XCTAssertEqual(StorageSnapshot.advertisedCapacity(forVolumeBytes: 250_000_000_000), 256_000_000_000)
        XCTAssertEqual(StorageSnapshot.advertisedCapacity(forVolumeBytes: 994_000_000_000), 1_024_000_000_000)
        XCTAssertEqual(StorageSnapshot.advertisedCapacity(forVolumeBytes: 60_000_000_000), 64_000_000_000)
    }

    func testUsedFractionIsOfAdvertisedCapacity() {
        let s = StorageSnapshot(date: start, totalBytes: 127_000_000_000, availableBytes: 1_000_000_000, availableForImportantUsageBytes: 1_000_000_000)
        XCTAssertEqual(s.usedBytes, 126_000_000_000)
        XCTAssertEqual(s.usedFraction, 126.0 / 128.0, accuracy: 0.0001)
    }

    func testPurgeableNeverNegative() {
        let s = StorageSnapshot(date: start, totalBytes: 100, availableBytes: 30, availableForImportantUsageBytes: 20)
        XCTAssertEqual(s.purgeableEstimateBytes, 0)
    }

    func testUsedNeverNegativeAndZeroTotalIsSafe() {
        let s = StorageSnapshot(date: start, totalBytes: 0, availableBytes: 10, availableForImportantUsageBytes: 10)
        XCTAssertEqual(s.usedBytes, 0)
        XCTAssertEqual(s.usedFraction, 0)
    }

    func testSnapshotRoundTripsThroughJSON() throws {
        var history = StorageHistory()
        history.append(snapshot(minutes: 0, free: 5, important: 9))
        let data = try JSONEncoder().encode(history)
        XCTAssertEqual(try JSONDecoder().decode(StorageHistory.self, from: data), history)
    }

    // MARK: Dedupe and cap

    func testSkipsReadingsUnderAMinuteApart() {
        var history = StorageHistory()
        XCTAssertTrue(history.append(snapshot(minutes: 0)))
        XCTAssertFalse(history.append(snapshot(minutes: 0.5)))
        XCTAssertFalse(history.append(snapshot(minutes: 0.99)))
        XCTAssertTrue(history.append(snapshot(minutes: 1)))
        XCTAssertEqual(history.snapshots.count, 2)
        XCTAssertEqual(history.latest?.date, start.addingTimeInterval(60))
    }

    func testKeepsAtMostFiveHundredDroppingOldest() {
        var history = StorageHistory()
        for i in 0..<520 {
            history.append(snapshot(minutes: Double(i) * 2))
        }
        XCTAssertEqual(history.snapshots.count, StorageHistory.maximumCount)
        XCTAssertEqual(history.snapshots.first?.date, start.addingTimeInterval(20 * 2 * 60))
        XCTAssertEqual(history.latest?.date, start.addingTimeInterval(519 * 2 * 60))
    }

    func testInitTrimsAndSortsLoadedSnapshots() {
        let loaded = (0..<510).reversed().map { snapshot(minutes: Double($0) * 2) }
        let history = StorageHistory(snapshots: loaded)
        XCTAssertEqual(history.snapshots.count, StorageHistory.maximumCount)
        XCTAssertEqual(history.snapshots.first?.date, start.addingTimeInterval(10 * 2 * 60))
        XCTAssertEqual(history.latest?.date, start.addingTimeInterval(509 * 2 * 60))
    }

    // MARK: change(over:)

    func testChangeIsNilWithoutEnoughData() {
        XCTAssertNil(StorageHistory().change(over: 3600))

        var history = StorageHistory()
        history.append(snapshot(minutes: 0, free: 10_000))
        XCTAssertNil(history.change(over: 3600), "One reading has nothing to compare against")

        history.append(snapshot(minutes: 30, free: 8_000))
        XCTAssertNil(history.change(over: 3600), "Readings only span 30 minutes")
    }

    func testChangeAcrossWindow() {
        var history = StorageHistory()
        history.append(snapshot(minutes: 0, free: 10_000))
        history.append(snapshot(minutes: 30, free: 9_000))
        history.append(snapshot(minutes: 90, free: 6_000))

        // Window of one hour from minute 90 starts at minute 30.
        XCTAssertEqual(history.change(over: 3600), -3_000)
        // Ninety minutes reaches the first reading exactly.
        XCTAssertEqual(history.change(over: 90 * 60), -4_000)
        XCTAssertEqual(history.change(over: 0), 0)
    }

    func testChangeIsPositiveWhenSpaceFreed() {
        var history = StorageHistory()
        history.append(snapshot(minutes: 0, free: 1_000))
        history.append(snapshot(minutes: 10, free: 5_000))
        XCTAssertEqual(history.change(over: 600), 4_000)
    }

    func testChangeIsNilWhenTheEarlierReadingIsMuchOlderThanTheWindow() {
        var history = StorageHistory()
        history.append(snapshot(minutes: 0, free: 10_000))
        // Forty days later, with nothing in between.
        history.append(snapshot(minutes: 40 * 24 * 60, free: 6_000))
        // A 3-day window would otherwise report the whole 40-day drop.
        XCTAssertNil(history.change(over: 3 * 86_400))
    }

    // MARK: Mock service

    func testMockServiceReportsItsNumbers() async throws {
        let date = start
        let service = MockDeviceStorageService(totalBytes: 100, availableBytes: 40, purgeableBytes: 5, now: { date })
        let s = try await service.currentSnapshot()
        XCTAssertEqual(s, StorageSnapshot(date: date, totalBytes: 100, availableBytes: 40, availableForImportantUsageBytes: 45))
    }
}
