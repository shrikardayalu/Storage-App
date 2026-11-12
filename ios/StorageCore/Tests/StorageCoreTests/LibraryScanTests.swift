import XCTest
@testable import StorageCore

final class LibraryScanTests: XCTestCase {
    func testItemsAreBiggestFirst() {
        let scan = LibraryScan(items: sampleScanItems())
        XCTAssertEqual(scan.items.first?.id, "prores")
        XCTAssertEqual(scan.items.map(\.currentBytes), scan.items.map(\.currentBytes).sorted(by: >))
    }

    func testEachItemHasExactlyOneKind() {
        let scan = LibraryScan(items: sampleScanItems())
        XCTAssertEqual(scan[.photos].count, 2) // still + ProRAW
        XCTAssertEqual(scan[.livePhotos].count, 1)
        XCTAssertEqual(scan[.bursts].count, 3)
        XCTAssertEqual(scan[.screenshots].count, 1)
        XCTAssertEqual(scan[.videos].count, 4)

        XCTAssertEqual(ScanGroup.kinds.map { scan[$0].count }.reduce(0, +), scan.total.count)
        XCTAssertEqual(ScanGroup.kinds.map { scan[$0].bytes }.reduce(0, +), scan.total.bytes)
        XCTAssertEqual(scan.total.bytes, 579_300)
    }

    func testBurstsCountDistinctBursts() {
        let scan = LibraryScan(items: sampleScanItems())
        XCTAssertEqual(scan.burstCount, 2)
        XCTAssertEqual(scan[.bursts].bytes, 3_000)
    }

    func testBigFormatsCutAcrossKinds() {
        let scan = LibraryScan(items: sampleScanItems())
        XCTAssertEqual(Set(scan.items(in: .bigFormats).map(\.id)), ["raw", "4k", "slomo", "prores"])
        XCTAssertEqual(scan[.bigFormats].bytes, 560_000)
    }

    func testFilteringKeepsBiggestFirst() {
        let scan = LibraryScan(items: sampleScanItems())
        XCTAssertEqual(scan.items(in: .videos).map(\.id), ["prores", "4k", "slomo", "hd"])
        XCTAssertEqual(scan.items(in: nil).count, 11)
    }

    func testEmptyScan() {
        let scan = LibraryScan(items: [])
        XCTAssertEqual(scan.total, .zero)
        XCTAssertEqual(scan[.videos], .zero)
        XCTAssertEqual(scan.burstCount, 0)
    }

    func testMockScanServiceErrors() async {
        let denied = MockPhotoScanService(items: [], access: .denied)
        do {
            _ = try await denied.scanLibrary()
            XCTFail("Expected an access error")
        } catch {
            XCTAssertEqual(error as? PhotoScanError, .accessDenied)
        }
    }

    func testMockScanReadsEverythingItMaySee() async throws {
        let full = MockPhotoScanService(items: sampleItems())
        let all = try await full.scanLibrary()
        XCTAssertEqual(all.count, sampleItems().count)

        // Limited access still scans: the items are just the ones the person picked.
        let limited = MockPhotoScanService(items: Array(sampleItems().prefix(2)), access: .limited)
        let picked = try await limited.scanLibrary()
        XCTAssertEqual(picked.count, 2)
    }
}
