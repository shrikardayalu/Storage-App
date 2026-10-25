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
