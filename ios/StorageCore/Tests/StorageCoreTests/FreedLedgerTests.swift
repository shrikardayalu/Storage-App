import XCTest
@testable import StorageCore

final class FreedLedgerTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let gb: Int64 = 1_000_000_000
    private let mb: Int64 = 1_000_000

    private func reading(minutes: Double, free: Int64) -> StorageSnapshot {
        StorageSnapshot(date: start.addingTimeInterval(minutes * 60), totalBytes: 128 * gb, availableBytes: free, availableForImportantUsageBytes: free)
    }

    func testPhotosCountOnceRecentlyDeletedIsEmptied() {
        var ledger = FreedLedger()
        let id = ledger.open(.photos, title: "Deleted 3 items", baseline: reading(minutes: 0, free: 10 * gb), expectedBytes: gb)
        ledger.record(reading(minutes: 1, free: 10 * gb))
        XCTAssertEqual(ledger.total, 0)
        XCTAssertEqual(ledger[id]?.isOpen, true, "Still waiting in Recently Deleted")

        ledger.record(reading(minutes: 5, free: 11 * gb))
        XCTAssertEqual(ledger.total, gb)
        XCTAssertEqual(ledger.total(for: .photos), gb)
        XCTAssertEqual(ledger[id]?.isOpen, false, "Closes once the whole size is back")
    }

    func testKnownSizeIsNeverExceeded() {
        var ledger = FreedLedger()
        ledger.open(.files, title: "Deleted 2 files", baseline: reading(minutes: 0, free: 10 * gb), expectedBytes: 500 * mb)
        // Something else freed space at the same time.
        ledger.record(reading(minutes: 1, free: 12 * gb))
        XCTAssertEqual(ledger.total, 500 * mb)
    }

    func testGainStaysCountedWhenFreeSpaceDipsLater() {
        var ledger = FreedLedger()
        let id = ledger.open(.guides, title: "WhatsApp", baseline: reading(minutes: 0, free: 10 * gb))
        ledger.record(reading(minutes: 2, free: 12 * gb))
        ledger.record(reading(minutes: 3, free: 9 * gb))
        XCTAssertEqual(ledger[id]?.measuredBytes, 2 * gb)
    }

    func testOverlappingActionsDontCountTheSameBytesTwice() {
        var ledger = FreedLedger()
        // Photos deleted, but Recently Deleted not emptied yet.
        ledger.open(.photos, title: "Deleted", baseline: reading(minutes: 0, free: 10 * gb), expectedBytes: gb)
        // Files deleted next: their space comes back at once.
        ledger.open(.files, title: "Files", baseline: reading(minutes: 1, free: 10 * gb), expectedBytes: 300 * mb)
        ledger.record(reading(minutes: 2, free: 10 * gb + 300 * mb))
        XCTAssertEqual(ledger.total(for: .files), 300 * mb)
        XCTAssertEqual(ledger.total(for: .photos), 0, "The files' space isn't the photos'")

        // Then Recently Deleted is emptied.
        ledger.record(reading(minutes: 10, free: 11 * gb + 300 * mb))
        XCTAssertEqual(ledger.total(for: .photos), gb)
        XCTAssertEqual(ledger.total, gb + 300 * mb)
    }

    func testTotalMatchesTheRealChangeInFreeSpace() {
        var ledger = FreedLedger()
        var free = 8 * gb
        ledger.open(.photos, title: "Deleted", baseline: reading(minutes: 0, free: free), expectedBytes: 700 * mb)
        ledger.open(.videos, title: "Shrank a video", baseline: reading(minutes: 1, free: free), expectedBytes: 400 * mb)
        free += 1_100 * mb // Recently Deleted emptied.
        ledger.record(reading(minutes: 3, free: free))
        let files = ledger.open(.files, title: "Files", baseline: reading(minutes: 4, free: free), expectedBytes: 250 * mb)
        free += 250 * mb
        ledger.record(reading(minutes: 4.5, free: free))
        ledger.close(files)
        let guide = ledger.open(.guides, title: "WhatsApp", baseline: reading(minutes: 6, free: free))
        free += 2 * gb
        ledger.record(reading(minutes: 8, free: free))
        ledger.close(guide)

        let now = reading(minutes: 9, free: free)
        XCTAssertEqual(ledger.total, ledger.freeSpaceChange(now: now))
        XCTAssertEqual(ledger.total(for: .photos) + ledger.total(for: .videos), 1_100 * mb)
        XCTAssertEqual(ledger.total(for: .guides), 2 * gb)
    }

    func testGuidesUnderTheNoiseFloorAreDropped() {
        var ledger = FreedLedger()
        let id = ledger.open(.guides, title: "Safari", baseline: reading(minutes: 0, free: 10 * gb))
        ledger.record(reading(minutes: 1, free: 10 * gb + 5 * mb))
        XCTAssertFalse(ledger[id]?.counts ?? true)
        XCTAssertEqual(ledger.total, 0)
        ledger.close(id)
        XCTAssertNil(ledger[id], "Closing an action that gave nothing back drops it")
        XCTAssertNil(ledger.start)
    }

    func testMeasuringStopsAfterTheWindow() {
        var ledger = FreedLedger()
        let id = ledger.open(.files, title: "Files", baseline: reading(minutes: 0, free: 10 * gb), expectedBytes: gb)
        ledger.record(reading(minutes: 1, free: 10 * gb + 400 * mb))
        ledger.record(reading(minutes: 20, free: 11 * gb))
        XCTAssertEqual(ledger[id]?.isOpen, false)
        XCTAssertEqual(ledger[id]?.measuredBytes, 400 * mb, "Readings after the window don't count")
    }

    func testReadingsFromBeforeAnActionAreIgnored() {
        var ledger = FreedLedger()
        ledger.open(.guides, title: "Messages", baseline: reading(minutes: 5, free: 10 * gb))
        ledger.record(reading(minutes: 1, free: 15 * gb))
        XCTAssertEqual(ledger.total, 0)
    }

    func testRoundTripsThroughJSON() throws {
        var ledger = FreedLedger()
        ledger.open(.photos, title: "Deleted", baseline: reading(minutes: 0, free: 10 * gb), expectedBytes: gb)
        ledger.record(reading(minutes: 1, free: 10 * gb + 400 * mb))
        let data = try JSONEncoder().encode(ledger)
        XCTAssertEqual(try JSONDecoder().decode(FreedLedger.self, from: data), ledger)
    }
}
