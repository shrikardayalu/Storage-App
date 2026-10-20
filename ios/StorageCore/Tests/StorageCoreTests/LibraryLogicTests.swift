import XCTest
@testable import StorageCore

final class SummaryTests: XCTestCase {
    func testTotalsDeriveFromItems() {
        let summary = LibrarySummary(items: sampleItems())
        XCTAssertEqual(summary.total.count, 7)
        XCTAssertEqual(summary.total.bytes, 697_100_000)
        XCTAssertEqual(summary[.photo], CategoryTotal(count: 3, bytes: 56_000_000))
        XCTAssertEqual(summary[.video], CategoryTotal(count: 2, bytes: 640_000_000))
        XCTAssertEqual(summary[.screenshot], CategoryTotal(count: 2, bytes: 1_100_000))
    }

    func testLargeVideosUseThreshold() {
        let summary = LibrarySummary(items: sampleItems())
        XCTAssertEqual(summary.largeVideos, CategoryTotal(count: 1, bytes: 600_000_000))
    }

    func testPotentialSavingsIsScreenshotsPlusBalancedCompression() {
        let items = sampleItems()
        let summary = LibrarySummary(items: items)
        let expectedCompression = items
            .filter { $0.category != .screenshot }
            .map { CompressionModel.estimate(for: $0, level: .balanced).savedBytes }
            .reduce(0, +)
        XCTAssertEqual(summary.compressionSavings, expectedCompression)
        XCTAssertEqual(summary.potentialSavings, 1_100_000 + expectedCompression)
        // ProRAW contributes nothing.
        XCTAssertEqual(expectedCompression, Int64(Double(4_000_000 + 2_000_000) * 0.38) + Int64(Double(640_000_000) * 0.55))
    }

    func testEmptyLibrary() {
        let summary = LibrarySummary(items: [])
        XCTAssertEqual(summary.total, .zero)
        XCTAssertEqual(summary[.video], .zero)
        XCTAssertEqual(summary.potentialSavings, 0)
    }
}

final class QueryTests: XCTestCase {
    func testFilters() {
        let items = sampleItems()
        XCTAssertEqual(MediaQuery.apply(filter: .all, sort: .largestFirst, to: items).count, 7)
        XCTAssertEqual(Set(MediaQuery.apply(filter: .photos, sort: .largestFirst, to: items).map(\.id)), ["p1", "p2", "raw"])
        XCTAssertEqual(Set(MediaQuery.apply(filter: .videos, sort: .largestFirst, to: items).map(\.id)), ["v1", "v2"])
        XCTAssertEqual(Set(MediaQuery.apply(filter: .screenshots, sort: .largestFirst, to: items).map(\.id)), ["s1", "s2"])
        XCTAssertEqual(MediaQuery.apply(filter: .largeVideos, sort: .largestFirst, to: items).map(\.id), ["v1"])
    }

    func testSortOrders() {
        let items = sampleItems()
        XCTAssertEqual(MediaQuery.apply(filter: .all, sort: .largestFirst, to: items).map(\.id), ["v1", "raw", "v2", "p1", "p2", "s1", "s2"])
        XCTAssertEqual(MediaQuery.apply(filter: .all, sort: .smallestFirst, to: items).map(\.id), ["s2", "s1", "p2", "p1", "v2", "raw", "v1"])
        XCTAssertEqual(MediaQuery.apply(filter: .all, sort: .newestFirst, to: items).map(\.id), ["p1", "v1", "s1", "s2", "p2", "raw", "v2"])
        XCTAssertEqual(MediaQuery.apply(filter: .all, sort: .oldestFirst, to: items).map(\.id), ["v2", "raw", "p2", "s2", "s1", "v1", "p1"])
    }

    func testTiesBreakByIDSoOrderIsStable() {
        let items = [makeItem(id: "b"), makeItem(id: "a"), makeItem(id: "c")]
        XCTAssertEqual(MediaQuery.apply(filter: .all, sort: .largestFirst, to: items).map(\.id), ["a", "b", "c"])
    }

    func testSortReflectsCompressedSize() throws {
        var library = MediaLibrary(items: [makeItem(id: "big", bytes: 10_000_000), makeItem(id: "mid", bytes: 7_000_000)])
        try library.compress(ids: ["big"], level: .maximum)
        XCTAssertEqual(MediaQuery.apply(filter: .all, sort: .largestFirst, to: library.items).map(\.id), ["mid", "big"])
    }

    func testEmptyInputGivesEmptyOutput() {
        for filter in MediaFilter.allCases {
            XCTAssertTrue(MediaQuery.apply(filter: filter, sort: .newestFirst, to: []).isEmpty)
        }
    }
}

final class SelectionTests: XCTestCase {
    func testToggleSelectsAndDeselects() {
        var selection = MediaSelection()
        selection.toggle("a")
        XCTAssertTrue(selection.contains("a"))
        selection.toggle("a")
        XCTAssertFalse(selection.contains("a"))
        XCTAssertTrue(selection.isEmpty)
    }

    func testSelectAllAndClear() {
        let items = sampleItems()
        var selection = MediaSelection()
        XCTAssertFalse(selection.containsAll(items))
        selection.select(items.map(\.id))
        XCTAssertEqual(selection.count, 7)
        XCTAssertTrue(selection.containsAll(items))
        selection.deselect(["p1"])
        XCTAssertFalse(selection.containsAll(items))
        selection.clear()
        XCTAssertTrue(selection.isEmpty)
    }

    func testContainsAllIsFalseForNoCandidates() {
        XCTAssertFalse(MediaSelection(ids: ["a"]).containsAll([]))
    }

    func testPruneDropsMissingIDs() {
        var selection = MediaSelection(ids: ["a", "b", "c"])
        selection.prune(keeping: ["b", "z"])
        XCTAssertEqual(selection.ids, ["b"])
    }
}
