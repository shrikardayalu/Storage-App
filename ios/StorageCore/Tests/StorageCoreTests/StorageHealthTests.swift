import XCTest
@testable import StorageCore

/// Build Plan step 9: low-space warnings and restart detection.
final class StorageHealthTests: XCTestCase {
    private func snapshot(free: Int64, total: Int64 = 119_000_000_000, at date: Date = referenceDate) -> StorageSnapshot {
        StorageSnapshot(date: date, totalBytes: total, availableBytes: free, availableForImportantUsageBytes: free)
    }

    func testPlentyOfSpaceIsFine() {
        XCTAssertNil(StorageWarning.evaluate(latest: snapshot(free: 30_000_000_000), history: StorageHistory()))
        XCTAssertNil(StorageWarning.evaluate(latest: nil, history: StorageHistory()))
    }

    func testLowSpaceWarns() {
        XCTAssertEqual(StorageWarning.evaluate(latest: snapshot(free: 4_000_000_000), history: StorageHistory()),
                       .low(availableBytes: 4_000_000_000))
    }

    func testSmallPhonesUseAShareOfCapacityButNeverUnderOneGigabyte() {
        // 64 GB phone: 5% is 3.2 GB.
        XCTAssertNil(StorageWarning.evaluate(latest: snapshot(free: 3_500_000_000, total: 59_000_000_000), history: StorageHistory()))
        XCTAssertNotNil(StorageWarning.evaluate(latest: snapshot(free: 3_000_000_000, total: 59_000_000_000), history: StorageHistory()))
        // 16 GB phone: 5% is 0.8 GB, but under 1 GB always warns.
        XCTAssertNotNil(StorageWarning.evaluate(latest: snapshot(free: 900_000_000, total: 14_000_000_000), history: StorageHistory()))
    }

    func testFastShrinkWarns() {
        let start = referenceDate
        let history = StorageHistory(snapshots: [
            snapshot(free: 30_000_000_000, at: start),
            snapshot(free: 26_000_000_000, at: start.addingTimeInterval(3 * 86_400 + 60)),
        ])
        XCTAssertEqual(StorageWarning.evaluate(latest: history.latest, history: history),
                       .shrinking(lostBytes: 4_000_000_000, days: 3))
    }

    func testSlowShrinkDoesNotWarn() {
        let history = StorageHistory(snapshots: [
            snapshot(free: 30_000_000_000, at: referenceDate),
            snapshot(free: 29_000_000_000, at: referenceDate.addingTimeInterval(4 * 86_400)),
        ])
        XCTAssertNil(StorageWarning.evaluate(latest: history.latest, history: history))
    }

    func testRestartIsDetectedWhenThePhoneStartedAfterTheBaseline() {
        let pending = PendingRestart(baseline: snapshot(free: 10_000_000_000))
        let now = referenceDate.addingTimeInterval(600)
        // Started 2 minutes ago, baseline was 10 minutes ago: restarted.
        XCTAssertTrue(pending.restarted(now: now, uptime: 120))
        // The in-app steps power off within a minute; that restart still counts.
        XCTAssertTrue(pending.restarted(now: now, uptime: 560))
        // Running for days: no restart, even if it slept.
        XCTAssertFalse(pending.restarted(now: now, uptime: 5 * 86_400))
        // Within the slack of the baseline: not counted.
        XCTAssertFalse(pending.restarted(now: now, uptime: 597))
        // A baseline in the future (clock changed) never counts.
        XCTAssertFalse(pending.restarted(now: referenceDate.addingTimeInterval(-10), uptime: 0))
    }

    func testGainAndExpiry() {
        let pending = PendingRestart(baseline: snapshot(free: 10_000_000_000))
        XCTAssertEqual(pending.gained(now: snapshot(free: 11_500_000_000)), 1_500_000_000)
        XCTAssertEqual(pending.gained(now: snapshot(free: 9_000_000_000)), 0)
        XCTAssertFalse(pending.isExpired(now: referenceDate.addingTimeInterval(86_400)))
        XCTAssertTrue(pending.isExpired(now: referenceDate.addingTimeInterval(4 * 86_400)))
    }

    func testTinyGainsDontCount() {
        XCTAssertFalse(RestartResult(date: referenceDate, gainedBytes: 5_000_000).gaveSpaceBack)
        XCTAssertTrue(RestartResult(date: referenceDate, gainedBytes: 500_000_000).gaveSpaceBack)
    }
}
