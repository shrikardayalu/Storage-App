import XCTest
@testable import StorageCore

/// PNG screenshots re-saved as smaller HEIC copies that keep their details.
final class ScreenshotResaveTests: XCTestCase {
    private func details(date: Date? = referenceDate, favorite: Bool = true, width: Int = 1179,
                         height: Int = 2556, inAlbum: Bool = true) -> AssetDetails {
        AssetDetails(creationDate: date, latitude: nil, longitude: nil, isFavorite: favorite,
                     pixelWidth: width, pixelHeight: height, isLivePhoto: false, inOriginalAlbums: inAlbum)
    }

    func testOnlyPNGScreenshotsAreResavable() {
        XCTAssertTrue(ScreenshotResave.isResavable(makeItem(id: "s", category: .screenshot)))
        XCTAssertFalse(ScreenshotResave.isResavable(makeItem(id: "h", category: .screenshot, format: .heic)))
        XCTAssertFalse(ScreenshotResave.isResavable(makeItem(id: "p", category: .photo, format: .png)))
        XCTAssertFalse(ScreenshotResave.isResavable(makeItem(id: "v", category: .video)))
    }

    func testEstimateIsCautious() {
        let shot = makeItem(id: "s", category: .screenshot, bytes: 2_000_000)
        XCTAssertEqual(ScreenshotResave.estimatedSaving(for: shot), 1_300_000)
        XCTAssertEqual(ScreenshotResave.estimatedBytes(for: shot), 700_000)
        XCTAssertEqual(ScreenshotResave.estimatedSaving(for: makeItem(id: "p", category: .photo)), 0)
    }

    func testCopyMustBeClearlySmaller() {
        XCTAssertTrue(ScreenshotResave.isWorthReplacing(originalBytes: 1_000_000, newBytes: 800_000))
        XCTAssertFalse(ScreenshotResave.isWorthReplacing(originalBytes: 1_000_000, newBytes: 800_001))
        XCTAssertFalse(ScreenshotResave.isWorthReplacing(originalBytes: 1_000_000, newBytes: 0))
    }

    func testMatchingCopyKeepsEverything() {
        let result = ResavedScreenshot(originalID: "o", newID: "n", original: details(),
                                       new: details(date: referenceDate.addingTimeInterval(0.3)),
                                       originalBytes: 2_000_000, newBytes: 500_000)
        XCTAssertTrue(result.keptEverything)
        XCTAssertEqual(result.savedBytes, 1_500_000)
    }

    func testEachLostDetailIsCaught() {
        let original = details()
        func copy(_ new: AssetDetails) -> ResavedScreenshot {
            ResavedScreenshot(originalID: "o", newID: "n", original: original, new: new, originalBytes: 2, newBytes: 1)
        }
        XCTAssertFalse(copy(details(date: referenceDate.addingTimeInterval(60))).keptDate)
        XCTAssertFalse(copy(details(favorite: false)).keptFavorite)
        XCTAssertFalse(copy(details(inAlbum: false)).keptAlbum)
        XCTAssertFalse(copy(details(width: 590)).isSameSize)
    }

    func testMockReplacesOnlyApprovedScreenshots() async throws {
        let big = makeItem(id: "big", category: .screenshot, bytes: 3_000_000)
        let other = makeItem(id: "other", category: .screenshot, bytes: 2_000_000)
        let library = MockPhotoLibrary(items: [big, other])
        let receipt = try await library.resaveScreenshots(["big"])
        XCTAssertEqual(receipt.resaved.map(\.originalID), ["big"])
        XCTAssertEqual(receipt.savedBytes, 1_950_000)
        let ids = await library.items.map(\.id)
        XCTAssertEqual(Set(ids), ["other", "big-heic"])
    }

    func testMockRefusesAnythingButPNGScreenshots() async {
        let library = MockPhotoLibrary(items: [makeItem(id: "photo")])
        do {
            _ = try await library.resaveScreenshots(["photo"])
            XCTFail("Expected a refusal")
        } catch {
            XCTAssertEqual(error as? PhotoChangeError, .notResavable(count: 1))
        }
        let count = await library.changeCount
        XCTAssertEqual(count, 0)
    }

    func testMockRefusesScreenshotsThatLeftTheLibrary() async {
        let library = MockPhotoLibrary(items: [makeItem(id: "s", category: .screenshot)])
        do {
            _ = try await library.resaveScreenshots(["s", "gone"])
            XCTFail("Expected a refusal")
        } catch {
            guard case .unsafe? = error as? PhotoChangeError else { return XCTFail("Wrong error: \(error)") }
        }
    }
}
