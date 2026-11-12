import XCTest
@testable import StorageCore

/// Step 4: a Live Photo becomes a still that keeps its details.
final class LiveStillTests: XCTestCase {
    private func details(
        date: Date? = referenceDate, lat: Double? = 40.5, lon: Double? = -74.4, favorite: Bool = true,
        width: Int = 4032, height: Int = 3024, live: Bool = false, inAlbum: Bool = true
    ) -> AssetDetails {
        AssetDetails(creationDate: date, latitude: lat, longitude: lon, isFavorite: favorite,
                     pixelWidth: width, pixelHeight: height, isLivePhoto: live, inOriginalAlbums: inAlbum)
    }

    func testMatchingStillKeepsEverything() {
        let result = StillConversion(
            originalID: "o", stillID: "s", original: details(live: true),
            still: details(date: referenceDate.addingTimeInterval(0.4)), savedBytes: 2_000_000
        )
        XCTAssertTrue(result.keptEverything)
    }

    func testEachLostDetailIsCaught() {
        let original = details(live: true)
        XCTAssertFalse(StillConversion(originalID: "o", stillID: "s", original: original, still: details(date: referenceDate.addingTimeInterval(3600)), savedBytes: 0).keptDate)
        XCTAssertFalse(StillConversion(originalID: "o", stillID: "s", original: original, still: details(lat: nil, lon: nil), savedBytes: 0).keptLocation)
        XCTAssertFalse(StillConversion(originalID: "o", stillID: "s", original: original, still: details(favorite: false), savedBytes: 0).keptFavorite)
        XCTAssertFalse(StillConversion(originalID: "o", stillID: "s", original: original, still: details(inAlbum: false), savedBytes: 0).keptAlbum)
        XCTAssertFalse(StillConversion(originalID: "o", stillID: "s", original: original, still: details(width: 1000), savedBytes: 0).isSameStill)
        XCTAssertFalse(StillConversion(originalID: "o", stillID: "s", original: original, still: details(live: true), savedBytes: 0).isSameStill)
    }

    func testOnlyNonBurstLivePhotosAreConvertible() {
        let items = sampleScanItems()
        XCTAssertEqual(items.filter(\.isConvertibleLivePhoto).map(\.id), ["live"])
    }

    func testMockConversionReplacesOnlyApprovedLivePhotos() async throws {
        let live = MediaItem(
            id: "live", category: .photo, format: .heic, filename: "IMG_1.HEIC", creationDate: referenceDate,
            pixelWidth: 4032, pixelHeight: 3024, duration: nil, originalBytes: 5_000_000, thumbnailSeed: 1,
            traits: .livePhoto, livePhotoVideoBytes: 3_000_000
        )
        let library = MockPhotoLibrary(items: [live, makeItem(id: "still")])
        let results = try await library.convertLivePhotosToStills(["live"])

        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results[0].keptEverything)
        XCTAssertEqual(results[0].savedBytes, 3_000_000)
        let items = await library.items
        XCTAssertEqual(Set(items.map(\.id)), ["still", "live-still"])
        XCTAssertFalse(items.contains { $0.traits.contains(.livePhoto) })
    }

    func testMockRefusesToConvertAPlainPhoto() async {
        let library = MockPhotoLibrary(items: [makeItem(id: "still")])
        do {
            _ = try await library.convertLivePhotosToStills(["still"])
            XCTFail("Converted a photo that isn't live")
        } catch {
            XCTAssertEqual(error as? PhotoChangeError, .notLivePhoto(count: 1))
        }
    }
}
