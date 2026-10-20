import XCTest
@testable import StorageCore

final class CompressionModelTests: XCTestCase {
    func testEstimateAppliesRatioToOriginalSize() {
        let video = makeItem(id: "v", category: .video, bytes: 100_000_000)
        XCTAssertEqual(CompressionModel.estimate(for: video, level: .balanced), .compressible(newBytes: 45_000_000, savedBytes: 55_000_000))
        let photo = makeItem(id: "p", category: .photo, bytes: 5_000_000)
        XCTAssertEqual(CompressionModel.estimate(for: photo, level: .light), .compressible(newBytes: 4_100_000, savedBytes: 900_000))
    }

    func testStrongerLevelsSaveMore() {
        let item = makeItem(id: "v", category: .video, bytes: 200_000_000)
        let light = CompressionModel.estimate(for: item, level: .light).savedBytes
        let balanced = CompressionModel.estimate(for: item, level: .balanced).savedBytes
        let maximum = CompressionModel.estimate(for: item, level: .maximum).savedBytes
        XCTAssertLessThan(light, balanced)
        XCTAssertLessThan(balanced, maximum)
    }

    func testUnsupportedFormatsAreIneligible() {
        let raw = makeItem(id: "r", category: .photo, format: .proRAW, bytes: 50_000_000)
        let proRes = makeItem(id: "pr", category: .video, format: .proRes, bytes: 5_000_000_000)
        XCTAssertEqual(CompressionModel.estimate(for: raw, level: .balanced), .ineligible(.unsupportedFormat(.proRAW)))
        XCTAssertEqual(CompressionModel.estimate(for: proRes, level: .maximum), .ineligible(.unsupportedFormat(.proRes)))
        XCTAssertFalse(raw.isCompressionEligible)
    }

    func testTinyFilesAreIneligible() {
        let tiny = makeItem(id: "t", category: .screenshot, bytes: 100_000)
        XCTAssertEqual(CompressionModel.estimate(for: tiny, level: .maximum), .ineligible(.tooSmall))
    }

    func testRepeatingSameLevelIsAlreadyOptimized() throws {
        var library = MediaLibrary(items: [makeItem(id: "p", bytes: 5_000_000)])
        try library.compress(ids: ["p"], level: .balanced)
        let compressed = library.items[0]
        XCTAssertEqual(CompressionModel.estimate(for: compressed, level: .balanced), .ineligible(.alreadyOptimized))
        XCTAssertEqual(CompressionModel.estimate(for: compressed, level: .light), .ineligible(.alreadyOptimized))
        XCTAssertEqual(CompressionModel.estimate(for: compressed, level: .maximum), .compressible(newBytes: 2_250_000, savedBytes: 850_000))
    }

    func testPlanTotalsAndGroupsSkippedItems() {
        let plan = CompressionPlan(items: sampleItems(), level: .balanced)
        // Eligible: p1, p2, v1, v2, s1. Skipped: raw (format), s2 (too small).
        XCTAssertEqual(plan.eligibleCount, 5)
        XCTAssertEqual(plan.bytesBefore, 4_000_000 + 2_000_000 + 600_000_000 + 40_000_000 + 1_000_000)
        XCTAssertEqual(plan.bytesAfter, 2_480_000 + 1_240_000 + 270_000_000 + 18_000_000 + 350_000)
        XCTAssertEqual(plan.savedBytes, plan.bytesBefore - plan.bytesAfter)
        XCTAssertEqual(plan.skippedCount, 2)
        XCTAssertEqual(Set(plan.skipped.map(\.reason)), [.unsupportedFormat(.proRAW), .tooSmall])
    }

    func testPlanWithOnlyUnsupportedItemsHasNoWork() {
        let plan = CompressionPlan(items: [makeItem(id: "r", format: .proRAW)], level: .light)
        XCTAssertFalse(plan.hasWork)
        XCTAssertEqual(plan.savedBytes, 0)
    }
}

final class MediaLibraryTests: XCTestCase {
    func testDeleteRemovesItemsAndUpdatesTotals() throws {
        var library = MediaLibrary(items: sampleItems())
        let before = library.summary.total.bytes
        let result = try library.delete(ids: ["v1", "s1"])
        XCTAssertEqual(result, CleanupResult(kind: .deletion, itemCount: 2, bytesRecovered: 601_000_000))
        XCTAssertEqual(library.items.count, 5)
        XCTAssertFalse(library.items.contains { $0.id == "v1" })
        XCTAssertEqual(library.summary.total.bytes, before - 601_000_000)
        XCTAssertEqual(library.savings.deletedBytes, 601_000_000)
    }

    func testDeleteWithUnknownIDsThrows() {
        var library = MediaLibrary(items: sampleItems())
        XCTAssertThrowsError(try library.delete(ids: ["nope"])) {
            XCTAssertEqual($0 as? MediaLibraryError, .noItemsSelected)
        }
    }

    func testUndoDeleteRestoresOriginalOrder() throws {
        let original = sampleItems()
        var library = MediaLibrary(items: original)
        try library.delete(ids: ["p1", "v2", "s2"])
        let undone = try library.undo()
        XCTAssertEqual(undone.kind, .deletion)
        XCTAssertEqual(library.items, original)
        XCTAssertEqual(library.savings, SessionSavings())
        XCTAssertFalse(library.canUndo)
    }

    func testUndoIsLastInFirstOut() throws {
        let original = sampleItems()
        var library = MediaLibrary(items: original)
        try library.delete(ids: ["p1"])
        try library.compress(ids: ["v1"], level: .light)
        try library.delete(ids: ["s1", "p2"])
        try library.undo()
        try library.undo()
        try library.undo()
        XCTAssertEqual(library.items, original)
        XCTAssertThrowsError(try library.undo())
    }

    func testCompressShrinksEligibleAndSkipsTheRest() throws {
        var library = MediaLibrary(items: sampleItems())
        let result = try library.compress(ids: ["v1", "raw", "s2"], level: .balanced)
        XCTAssertEqual(result.itemCount, 1)
        XCTAssertEqual(result.skippedCount, 2)
        XCTAssertEqual(result.bytesRecovered, 330_000_000)
        let video = try XCTUnwrap(library.items.first { $0.id == "v1" })
        XCTAssertEqual(video.currentBytes, 270_000_000)
        XCTAssertEqual(video.originalBytes, 600_000_000)
        XCTAssertEqual(video.compressionLevel, .balanced)
        XCTAssertEqual(library.items.first { $0.id == "raw" }?.isCompressed, false)
        XCTAssertEqual(library.savings.compressedBytes, 330_000_000)
    }

    func testCompressWithNothingEligibleThrows() {
        var library = MediaLibrary(items: sampleItems())
        XCTAssertThrowsError(try library.compress(ids: ["raw", "s2"], level: .maximum)) {
            XCTAssertEqual($0 as? MediaLibraryError, .nothingToCompress)
        }
        XCTAssertFalse(library.canUndo)
    }

    func testUndoCompressionRestoresSizes() throws {
        let original = sampleItems()
        var library = MediaLibrary(items: original)
        try library.compress(ids: ["p1", "p2", "v1"], level: .maximum)
        XCTAssertLessThan(library.summary.total.bytes, LibrarySummary(items: original).total.bytes)
        try library.undo()
        XCTAssertEqual(library.items, original)
        XCTAssertEqual(library.savings.compressedBytes, 0)
    }

    func testDeletingCompressedItemRecoversCurrentSize() throws {
        var library = MediaLibrary(items: sampleItems())
        try library.compress(ids: ["v1"], level: .balanced)
        let result = try library.delete(ids: ["v1"])
        XCTAssertEqual(result.bytesRecovered, 270_000_000)
    }

    func testEmptyLibraryOperations() {
        var library = MediaLibrary(items: [])
        XCTAssertEqual(library.summary.total, .zero)
        XCTAssertThrowsError(try library.delete(ids: ["a"]))
        XCTAssertThrowsError(try library.compress(ids: [], level: .light))
        XCTAssertThrowsError(try library.undo())
    }
}
