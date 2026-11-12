import XCTest
@testable import StorageCore

/// Step 5: exactly one photo per burst is left, the one the person picked.
final class BurstPickTests: XCTestCase {
    private func shot(_ id: String, burst: String?, bytes: Int64 = 1_000, second: Double = 0, pick: Bool = false) -> MediaItem {
        MediaItem(
            id: id, category: .photo, format: .heic, filename: "\(id).HEIC",
            creationDate: referenceDate.addingTimeInterval(second), pixelWidth: 4032, pixelHeight: 3024,
            duration: nil, originalBytes: bytes, thumbnailSeed: 1,
            traits: pick ? .burstPick : [], burstID: burst
        )
    }

    /// Two bursts of three and two shots, a lone shot left over from a burst, and a plain photo.
    private func album() -> [MediaItem] {
        [
            shot("a1", burst: "A", bytes: 1_000, second: 0),
            shot("a2", burst: "A", bytes: 2_000, second: 0.1, pick: true),
            shot("a3", burst: "A", bytes: 3_000, second: 0.2),
            shot("b1", burst: "B", bytes: 500, second: 5),
            shot("b2", burst: "B", bytes: 600, second: 5.1),
            shot("c1", burst: "C"),
            shot("plain", burst: nil),
        ]
    }

    private func burstsLeft(_ items: [MediaItem]) -> [String: [MediaItem.ID]] {
        Dictionary(grouping: items.filter { $0.burstID != nil }, by: { $0.burstID! }).mapValues { $0.map(\.id).sorted() }
    }

    // MARK: Grouping

    func testBurstsNeedTwoShotsAndAreOrderedByTime() {
        let bursts = Burst.all(in: album())
        XCTAssertEqual(Set(bursts.map(\.id)), ["A", "B"])
        XCTAssertEqual(bursts.first { $0.id == "A" }?.shots.map(\.id), ["a1", "a2", "a3"])
    }

    func testSuggestedKeeperIsTheCameraPickElseTheMiddleShot() {
        let bursts = Burst.all(in: album())
        XCTAssertEqual(bursts.first { $0.id == "A" }?.suggestedKeeper, "a2")
        XCTAssertEqual(bursts.first { $0.id == "B" }?.suggestedKeeper, "b2")
    }

    func testSavingIsEveryOtherShot() {
        let a = Burst.all(in: album()).first { $0.id == "A" }!
        XCTAssertEqual(a.savedBytes(keeping: "a1"), 5_000)
        XCTAssertEqual(a.savedBytes(keeping: "a3"), 3_000)
    }

    // MARK: Plan

    func testPlanRefusesAnythingButOneReviewedKeeperPerBurst() {
        let members = Dictionary(uniqueKeysWithValues: album().map { ($0.id, $0.burstID) })
        XCTAssertNoThrow(try BurstPlan.make(keep: ["a3"], expectedRemove: ["a1", "a2"], members: members))
        // Two keepers in one burst.
        XCTAssertThrowsError(try BurstPlan.make(keep: ["a1", "a2"], expectedRemove: ["a3"], members: members))
        // A keeper that isn't in a burst, or isn't in the album.
        XCTAssertThrowsError(try BurstPlan.make(keep: ["plain"], expectedRemove: [], members: members))
        XCTAssertThrowsError(try BurstPlan.make(keep: ["gone"], expectedRemove: ["a1"], members: members))
        // The review missed a shot, or listed one from another burst.
        XCTAssertThrowsError(try BurstPlan.make(keep: ["a3"], expectedRemove: ["a1"], members: members))
        XCTAssertThrowsError(try BurstPlan.make(keep: ["a3"], expectedRemove: ["a1", "a2", "b1"], members: members))
        // Nothing to do.
        XCTAssertThrowsError(try BurstPlan.make(keep: ["c1"], expectedRemove: [], members: members))
    }

    func testAuditCatchesAKeeperThatWentMissing() throws {
        let before = Dictionary(uniqueKeysWithValues: album().map { ($0.id, $0.burstID) })
        let plan = try BurstPlan.make(keep: ["a1"], expectedRemove: ["a2", "a3"], members: before)
        var after = before
        for id in ["a1", "a2", "a3"] { after.removeValue(forKey: id) }
        let receipt = BurstReceipt.audit(plan: plan, before: before, after: after, removedBytes: 0)
        XCTAssertFalse(receipt.isExact)
        XCTAssertTrue(receipt.keptPick.isEmpty)
    }

    // MARK: The Build Plan test, on the mock album

    func testExactlyThePickedShotIsLeftInEachBurst() async throws {
        let library = MockPhotoLibrary(items: album())
        let receipt = try await library.keepBurstPicks(keep: ["a3", "b1"], remove: ["a1", "a2", "b2"])

        XCTAssertTrue(receipt.isExact)
        XCTAssertEqual(receipt.keptPick, ["A", "B"])
        XCTAssertEqual(receipt.removed, ["a1", "a2", "b2"])
        XCTAssertEqual(receipt.removedBytes, 3_600)
        XCTAssertEqual(receipt.countBefore - receipt.countAfter, 3)
        let items = await library.items
        XCTAssertEqual(burstsLeft(items), ["A": ["a3"], "B": ["b1"], "C": ["c1"]])
        XCTAssertTrue(items.contains { $0.id == "plain" })
    }

    func testSkippedBurstIsLeftAlone() async throws {
        let library = MockPhotoLibrary(items: album())
        _ = try await library.keepBurstPicks(keep: ["b2"], remove: ["b1"])
        let left = burstsLeft(await library.items)
        XCTAssertEqual(left["A"], ["a1", "a2", "a3"])
        XCTAssertEqual(left["B"], ["b2"])
    }

    func testShotThatLeftTheLibraryBlocksTheWholeChange() async {
        let library = MockPhotoLibrary(items: album())
        do {
            _ = try await library.keepBurstPicks(keep: ["a2", "b1"], remove: ["a1", "a3", "b2", "gone"])
            XCTFail("Ran with a shot that isn't in the library")
        } catch {
            guard case .burstsChanged? = error as? PhotoChangeError else { return XCTFail("Wrong error: \(error)") }
        }
        let count = await library.items.count
        let changes = await library.changeCount
        XCTAssertEqual(count, album().count)
        XCTAssertEqual(changes, 0)
    }

    func testStaleReviewChangesNothing() async {
        let library = MockPhotoLibrary(items: album())
        do {
            _ = try await library.keepBurstPicks(keep: ["a1"], remove: ["a2"])
            XCTFail("Ran with a review that missed a shot")
        } catch {
            guard case .burstsChanged? = error as? PhotoChangeError else { return XCTFail("Wrong error: \(error)") }
        }
        let changes = await library.changeCount
        XCTAssertEqual(changes, 0)
    }

    func testDecliningIOSPromptChangesNothing() async {
        let library = MockPhotoLibrary(items: album())
        await library.setDeclinesChanges(true)
        do {
            _ = try await library.keepBurstPicks(keep: ["a1"], remove: ["a2", "a3"])
            XCTFail("Changed after the prompt was declined")
        } catch {
            XCTAssertEqual(error as? PhotoChangeError, .cancelled)
        }
        let count = await library.items.count
        XCTAssertEqual(count, album().count)
    }
}
