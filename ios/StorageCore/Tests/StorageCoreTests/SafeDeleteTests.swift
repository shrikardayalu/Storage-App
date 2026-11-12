import XCTest
@testable import StorageCore

/// Step 3's rule: only items the person approved, and that are still in the library, are ever changed.
final class SafeDeleteTests: XCTestCase {
    func testSafetyCheckPassesApprovedItemsStillInTheLibrary() {
        let check = SafetyCheck.evaluate(approved: ["a", "b"], found: ["a", "b"])
        XCTAssertTrue(check.isSafe)
        XCTAssertEqual(check.verified, ["a", "b"])
        XCTAssertNil(check.problem)
    }

    func testSafetyCheckBlocksItemsNoLongerInTheLibrary() {
        let check = SafetyCheck.evaluate(approved: ["a", "gone"], found: ["a"])
        XCTAssertFalse(check.isSafe)
        XCTAssertEqual(check.missing, ["gone"])
        XCTAssertEqual(check.verified, ["a"])
        XCTAssertNotNil(check.problem)
    }

    func testEmptyApprovalIsNeverSafe() {
        XCTAssertFalse(SafetyCheck.evaluate(approved: [], found: []).isSafe)
    }

    func testAuditAllowsItemsAddedMeanwhile() {
        // A photo taken, or synced from iCloud, during the change isn't a problem.
        let receipt = DeletionReceipt.audit(approved: ["a"], before: ["a", "b"], after: ["b", "new"], deletedBytes: 10)
        XCTAssertTrue(receipt.onlyApprovedRemoved)
        XCTAssertEqual(receipt.deleted, ["a"])
    }

    func testCountAuditPassesOnlyWhenExactlyTheApprovedLeft() {
        let good = DeletionReceipt.audit(approved: ["a", "b"], stillPresent: [], countBefore: 10, countAfter: 8, deletedBytes: 10)
        XCTAssertTrue(good.onlyApprovedRemoved)
        XCTAssertEqual(good.deleted, ["a", "b"])

        // One approved item is still there.
        let left = DeletionReceipt.audit(approved: ["a", "b"], stillPresent: ["b"], countBefore: 10, countAfter: 9, deletedBytes: 10)
        XCTAssertFalse(left.onlyApprovedRemoved)
        XCTAssertEqual(left.deleted, ["a"])

        // The library shrank by more than what was approved.
        let extra = DeletionReceipt.audit(approved: ["a", "b"], stillPresent: [], countBefore: 10, countAfter: 7, deletedBytes: 10)
        XCTAssertFalse(extra.onlyApprovedRemoved)

        // A new photo arrived meanwhile.
        let added = DeletionReceipt.audit(approved: ["a", "b"], stillPresent: [], countBefore: 10, countAfter: 9, deletedBytes: 10)
        XCTAssertTrue(added.onlyApprovedRemoved)
    }

    func testAuditFlagsAnyExtraRemoval() {
        let good = DeletionReceipt.audit(approved: ["a"], before: ["a", "b", "c"], after: ["b", "c"], deletedBytes: 10)
        XCTAssertTrue(good.onlyApprovedRemoved)
        XCTAssertEqual(good.countBefore, 3)
        XCTAssertEqual(good.countAfter, 2)

        let extra = DeletionReceipt.audit(approved: ["a"], before: ["a", "b", "c"], after: ["c"], deletedBytes: 10)
        XCTAssertFalse(extra.onlyApprovedRemoved)
        XCTAssertEqual(extra.deleted, ["a", "b"])
    }

    func testMockDeletesOnlyTheApprovedItems() async throws {
        let library = MockPhotoLibrary(items: sampleItems())
        let receipt = try await library.delete(["p1", "v1"])

        XCTAssertTrue(receipt.onlyApprovedRemoved)
        XCTAssertEqual(receipt.deleted, ["p1", "v1"])
        XCTAssertEqual(receipt.deletedBytes, 604_000_000)
        let remaining = await library.items.map(\.id)
        XCTAssertEqual(Set(remaining), ["p2", "raw", "v2", "s1", "s2"])
    }

    func testMockRefusesTheWholeDeleteWhenOneItemFails() async {
        let library = MockPhotoLibrary(items: sampleItems())

        for approved: Set<String> in [["p1", "not-in-library"], ["gone-1", "gone-2"]] {
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

    func testReclaimCountsSpaceIOSMarkedPurgeable() {
        var measurement = ReclaimMeasurement(baseline: snapshot(free: 5_000_000_000, at: 0), expectedBytes: 1_000_000_000)
        // Emptied, but iOS only marked the space purgeable so far.
        measurement.record(StorageSnapshot(
            date: referenceDate.addingTimeInterval(60), totalBytes: 128_000_000_000,
            availableBytes: 5_000_000_000, availableForImportantUsageBytes: 5_900_000_000
        ))
        XCTAssertEqual(measurement.reclaimedBytes, 900_000_000)
        XCTAssertTrue(measurement.isDone)
    }
}
