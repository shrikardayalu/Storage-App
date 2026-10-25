import XCTest
@testable import StorageCore

/// Step 3's rule: only approved items in the test album are ever changed.
final class SafeDeleteTests: XCTestCase {
    func testSafetyCheckPassesOnlyApprovedAlbumItems() {
        let check = SafetyCheck.evaluate(approved: ["a", "b"], testAlbumMembers: ["a", "b", "c"], otherAlbumMembers: [])
        XCTAssertTrue(check.isSafe)
        XCTAssertEqual(check.verified, ["a", "b"])
        XCTAssertNil(check.problem)
    }

    func testSafetyCheckBlocksItemsOutsideTheAlbum() {
        let check = SafetyCheck.evaluate(approved: ["a", "elsewhere"], testAlbumMembers: ["a", "b"], otherAlbumMembers: [])
        XCTAssertFalse(check.isSafe)
        XCTAssertEqual(check.outsideTestAlbum, ["elsewhere"])
        XCTAssertNotNil(check.problem)
    }

    func testSafetyCheckBlocksItemsAlsoInAnotherAlbum() {
        let check = SafetyCheck.evaluate(approved: ["a", "b"], testAlbumMembers: ["a", "b"], otherAlbumMembers: ["b"])
        XCTAssertFalse(check.isSafe)
        XCTAssertEqual(check.inOtherAlbums, ["b"])
        XCTAssertEqual(check.verified, ["a"])
    }

    func testEmptyApprovalIsNeverSafe() {
        XCTAssertFalse(SafetyCheck.evaluate(approved: [], testAlbumMembers: ["a"], otherAlbumMembers: []).isSafe)
    }

    func testAuditFlagsAnyExtraRemoval() {
        let good = DeletionReceipt.audit(approved: ["a"], before: ["a", "b", "c"], after: ["b", "c"], deletedBytes: 10)
        XCTAssertTrue(good.onlyApprovedRemoved)
        XCTAssertEqual(good.albumCountBefore, 3)
        XCTAssertEqual(good.albumCountAfter, 2)

        let extra = DeletionReceipt.audit(approved: ["a"], before: ["a", "b", "c"], after: ["c"], deletedBytes: 10)
        XCTAssertFalse(extra.onlyApprovedRemoved)
        XCTAssertEqual(extra.deleted, ["a", "b"])
    }

    func testMockDeletesOnlyTheApprovedItems() async throws {
        let outside = makeItem(id: "not-in-album")
        let library = MockPhotoLibrary(items: sampleItems(), outsideItems: [outside])
        let receipt = try await library.delete(["p1", "v1"])

        XCTAssertTrue(receipt.onlyApprovedRemoved)
        XCTAssertEqual(receipt.deleted, ["p1", "v1"])
        XCTAssertEqual(receipt.deletedBytes, 604_000_000)
        let remaining = await library.items.map(\.id)
        XCTAssertEqual(Set(remaining), ["p2", "raw", "v2", "s1", "s2"])
        let untouched = await library.outsideItems
        XCTAssertEqual(untouched, [outside])
    }

    func testMockRefusesTheWholeDeleteWhenOneItemFails() async {
        let outside = makeItem(id: "not-in-album")
        let library = MockPhotoLibrary(items: sampleItems(), inOtherAlbums: ["p2"], outsideItems: [outside])

        for approved: Set<String> in [["p1", "not-in-album"], ["p1", "p2"]] {
            do {
                _ = try await library.delete(approved)
                XCTFail("Deleted \(approved) despite a failing item")
            } catch let PhotoChangeError.unsafe(check) {
                XCTAssertFalse(check.isSafe)
            } catch {
                XCTFail("Unexpected error \(error)")
            }
        }
        let count = await library.items.count
        let changes = await library.changeCount
        XCTAssertEqual(count, sampleItems().count)
        XCTAssertEqual(changes, 0)
    }

    func testLimitedAccessCannotChangeAnything() async {
        let library = MockPhotoLibrary(items: sampleItems(), access: .limited)
        do {
            _ = try await library.delete(["p1"])
            XCTFail("Deleted with limited access")
        } catch {
            XCTAssertEqual(error as? PhotoChangeError, .needsFullAccess)
        }
    }

    func testDeclinedSystemPromptChangesNothing() async {
        let library = MockPhotoLibrary(items: sampleItems())
        await library.setDeclinesChanges(true)
        do {
            _ = try await library.delete(["p1"])
            XCTFail("Deleted after the prompt was declined")
        } catch {
            XCTAssertEqual(error as? PhotoChangeError, .cancelled)
        }
        let count = await library.items.count
        XCTAssertEqual(count, sampleItems().count)
    }

    // MARK: Measuring the space that comes back

    private func snapshot(free: Int64, at seconds: TimeInterval) -> StorageSnapshot {
        StorageSnapshot(
            date: referenceDate.addingTimeInterval(seconds), totalBytes: 128_000_000_000,
            availableBytes: free, availableForImportantUsageBytes: free
        )
    }

    func testReclaimMeasuresGainSinceBaseline() {
        var measurement = ReclaimMeasurement(baseline: snapshot(free: 5_000_000_000, at: 0), expectedBytes: 1_000_000_000)
        XCTAssertEqual(measurement.reclaimedBytes, 0)
        XCTAssertFalse(measurement.isDone)

        measurement.record(snapshot(free: 5_200_000_000, at: 60))
        XCTAssertEqual(measurement.reclaimedBytes, 200_000_000)
        XCTAssertFalse(measurement.isDone)

        measurement.record(snapshot(free: 5_950_000_000, at: 120))
        XCTAssertEqual(measurement.fraction, 0.95, accuracy: 0.001)
        XCTAssertTrue(measurement.isDone)
    }

    func testReclaimIgnoresDropsAndOlderReadings() {
        var measurement = ReclaimMeasurement(baseline: snapshot(free: 5_000_000_000, at: 100), expectedBytes: 1_000_000_000)
        measurement.record(snapshot(free: 4_000_000_000, at: 200))
        XCTAssertEqual(measurement.reclaimedBytes, 0)
        measurement.record(snapshot(free: 9_000_000_000, at: 50))
        XCTAssertEqual(measurement.reclaimedBytes, 0)
    }
}
