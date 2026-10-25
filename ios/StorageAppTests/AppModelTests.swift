import StorageCore
import XCTest
@testable import StorageApp

/// Tests for the app's shared state, run against mock services.
/// Pure business logic is covered in StorageCore's own tests.
@MainActor
final class AppModelTests: XCTestCase {
    private func makeHistoryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("history-\(UUID().uuidString).json")
    }

    // MARK: Device storage

    func testStorageReadingIsShownAndSavedOncePerMinute() async throws {
        let url = makeHistoryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let service = MockDeviceStorageService(totalBytes: 100, availableBytes: 40, purgeableBytes: 5)
        let model = AppModel(storage: service, historyStore: StorageHistoryStore(fileURL: url))

        await model.refreshDeviceStorage()
        await model.refreshDeviceStorage()
        XCTAssertEqual(model.deviceStorage?.availableBytes, 40)
        XCTAssertEqual(model.storageHistory.snapshots.count, 1)

        // A new launch loads the saved history.
        let reloaded = AppModel(historyStore: StorageHistoryStore(fileURL: url))
        XCTAssertEqual(reloaded.storageHistory.snapshots.count, 1)
        XCTAssertEqual(reloaded.deviceStorage?.purgeableEstimateBytes, 5)
    }

    func testCorruptHistoryFileStartsFresh() throws {
        let url = makeHistoryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not json".utf8).write(to: url)
        XCTAssertTrue(StorageHistoryStore(fileURL: url).load().snapshots.isEmpty)
    }

    // MARK: Test album scan

    func testScanGroupsTestAlbum() async {
        let items = [
            MediaItem(id: "a", category: .photo, format: .heic, filename: "a.HEIC", creationDate: Date(),
                      pixelWidth: 4032, pixelHeight: 3024, duration: nil, originalBytes: 3_000_000, thumbnailSeed: 0),
            MediaItem(id: "b", category: .video, format: .hevc, filename: "b.MOV", creationDate: Date(),
                      pixelWidth: 3840, pixelHeight: 2160, duration: 60, originalBytes: 400_000_000, thumbnailSeed: 0),
        ]
        let model = AppModel(photoScanner: MockPhotoScanService(items: items))
        await model.scanTestAlbum()
        XCTAssertNil(model.scanError)
        XCTAssertEqual(model.albumScan?.total.count, 2)
        XCTAssertEqual(model.albumScan?.items.first?.id, "b")
        XCTAssertEqual(model.albumScan?[.bigFormats].count, 1)
    }

    func testScanReportsMissingAlbumAndDeniedAccess() async {
        let missing = AppModel(photoScanner: MockPhotoScanService(items: [], albumExists: false))
        await missing.scanTestAlbum()
        XCTAssertEqual(missing.scanError, .albumNotFound(TestMode.albumName))
        XCTAssertNil(missing.albumScan)

        let denied = AppModel(photoScanner: MockPhotoScanService(items: [], access: .denied))
        await denied.scanTestAlbum()
        XCTAssertEqual(denied.scanError, .accessDenied)
    }

    func testScanIfAllowedNeverPrompts() async {
        let model = AppModel(photoScanner: MockPhotoScanService(items: [], access: .notDetermined))
        await model.scanIfAllowed()
        XCTAssertNil(model.albumScan)
        XCTAssertEqual(model.photoAccess, .notDetermined)
    }

    func testShowLibraryNavigatesWithGroup() {
        let model = AppModel()
        model.showLibrary(group: .videos)
        XCTAssertEqual(model.selectedTab, .library)
        XCTAssertEqual(model.libraryGroup, .videos)
    }

    // MARK: Safe delete (Build Plan step 3)

    private func item(_ id: String, bytes: Int64 = 1_000_000, live: Int64? = nil) -> MediaItem {
        MediaItem(id: id, category: .photo, format: .heic, filename: "\(id).HEIC", creationDate: Date(),
                  pixelWidth: 4032, pixelHeight: 3024, duration: nil, originalBytes: bytes, thumbnailSeed: 0,
                  traits: live == nil ? [] : .livePhoto, livePhotoVideoBytes: live ?? 0)
    }

    func testDeletingRemovesOnlyApprovedItemsAndOpensGuide() async {
        let library = MockPhotoLibrary(items: [item("a"), item("b"), item("c")])
        let model = AppModel(library: library)
        await model.scanTestAlbum()
        model.toggleSelection("a")
        model.toggleSelection("b")

        // Only "a" is still on the receipt when Delete is tapped.
        let error = await model.delete(approved: ["a"])
        XCTAssertNil(error)
        let remaining = await library.items.map(\.id)
        XCTAssertEqual(Set(remaining), ["b", "c"])
        XCTAssertEqual(Set(model.albumScan?.items.map(\.id) ?? []), ["b", "c"])
        XCTAssertFalse(model.selection.contains("a"))
        guard case .deleted(let receipt)? = model.guide?.kind else { return XCTFail("No guide") }
        XCTAssertTrue(receipt.onlyApprovedRemoved)
        XCTAssertEqual(model.reclaim?.expectedBytes, 1_000_000)
    }

    func testNothingOutsideTheScanCanBeSelected() async {
        let model = AppModel(library: MockPhotoLibrary(items: [item("a")]))
        await model.scanTestAlbum()
        model.toggleSelection("someone-elses-photo")
        XCTAssertTrue(model.selection.isEmpty)
    }

    func testUnsafeDeleteChangesNothing() async {
        let library = MockPhotoLibrary(items: [item("a"), item("b")], inOtherAlbums: ["b"])
        let model = AppModel(library: library)
        await model.scanTestAlbum()

        let error = await model.delete(approved: ["a", "b"])
        guard case .unsafe? = error else { return XCTFail("Expected the safety check to block it") }
        let count = await library.items.count
        XCTAssertEqual(count, 2)
        XCTAssertNil(model.guide)
    }

    func testGuideWaitsForReviewSheetToClose() async {
        let model = AppModel(library: MockPhotoLibrary(items: [item("a")]))
        await model.scanTestAlbum()
        model.isReviewing = true
        await model.delete(approved: ["a"])
        XCTAssertFalse(model.isReviewing)
        XCTAssertNil(model.guide)
        model.presentPendingGuide()
        XCTAssertNotNil(model.guide)
    }

    // MARK: Live Photos → stills (Build Plan step 4)

    func testConvertingLivePhotosReplacesThemWithStills() async {
        let library = MockPhotoLibrary(items: [item("live", bytes: 5_000_000, live: 3_000_000), item("still")])
        let model = AppModel(library: library)
        await model.scanTestAlbum()
        XCTAssertEqual(model.convertibleLivePhotos.map(\.id), ["live"])

        let error = await model.convertToStills(approved: ["live"])
        XCTAssertNil(error)
        XCTAssertTrue(model.convertibleLivePhotos.isEmpty)
        XCTAssertEqual(model.albumScan?.total.count, 2)
        guard case .convertedLivePhotos(let results)? = model.guide?.kind else { return XCTFail("No guide") }
        XCTAssertTrue(results.allSatisfy(\.keptEverything))
        XCTAssertEqual(model.guide?.expectedBytes, 3_000_000)
    }
}
