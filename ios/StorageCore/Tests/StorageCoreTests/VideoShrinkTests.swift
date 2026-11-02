import XCTest
@testable import StorageCore

/// Step 6: videos get smaller (and optionally trimmed) and keep their details.
final class VideoShrinkTests: XCTestCase {
    /// A 60-second 4K video at about 45 Mbps.
    private func video(
        id: String = "v", width: Int = 3840, height: Int = 2160, duration: TimeInterval = 60,
        bytes: Int64 = 340_000_000, format: MediaFormat = .h264, traits: MediaTraits = []
    ) -> MediaItem {
        MediaItem(id: id, category: .video, format: format, filename: "\(id).MOV", creationDate: referenceDate,
                  pixelWidth: width, pixelHeight: height, duration: duration, originalBytes: bytes,
                  thumbnailSeed: 1, traits: traits)
    }

    private func details(
        date: Date? = referenceDate, lat: Double? = 40.5, favorite: Bool = true,
        duration: TimeInterval = 60, bytes: Int64 = 340_000_000, isVideo: Bool = true, inAlbum: Bool = true
    ) -> VideoDetails {
        VideoDetails(creationDate: date, latitude: lat, longitude: lat.map { -$0 }, isFavorite: favorite,
                     duration: duration, bytes: bytes, isVideo: isVideo, inTestAlbum: inAlbum)
    }

    // MARK: Trim

    func testTrimStaysInsideTheVideoAndAtLeastOneSecond() {
        XCTAssertEqual(VideoTrim(start: -3, end: 90).clamped(to: 60), VideoTrim(start: 0, end: 60))
        XCTAssertEqual(VideoTrim(start: 30, end: 30.2).clamped(to: 60), VideoTrim(start: 29.2, end: 30.2))
        XCTAssertEqual(VideoTrim(start: 59.8, end: 0.1).clamped(to: 60), VideoTrim(start: 0, end: 1))
        XCTAssertEqual(VideoTrim(start: 10, end: 20).clamped(to: 0.5), VideoTrim.full(0.5))
    }

    func testFullTrimIsRecognized() {
        XCTAssertTrue(VideoTrim.full(60).isFull(of: 60))
        XCTAssertTrue(VideoTrim(start: 0.01, end: 59.99).isFull(of: 60))
        XCTAssertFalse(VideoTrim(start: 2, end: 60).isFull(of: 60))
        XCTAssertFalse(VideoTrim(start: 0, end: 50).isFull(of: 60))
    }

    // MARK: Which videos

    func testOnlyEditableVideosAreShrinkable() {
        XCTAssertTrue(video().isShrinkableVideo)
        XCTAssertFalse(video(format: .proRes).isShrinkableVideo)
        XCTAssertFalse(video(traits: .slowMotion).isShrinkableVideo)
        XCTAssertFalse(video(traits: .cinematic).isShrinkableVideo)
        XCTAssertFalse(video(bytes: 1_000_000).isShrinkableVideo)
        XCTAssertFalse(video(duration: 0.5).isShrinkableVideo)
        XCTAssertFalse(makeItem(id: "p", category: .photo, bytes: 50_000_000).isShrinkableVideo)
    }

    // MARK: Estimates

    func testOutputSizeCapsTheLongSideAt1080p() {
        XCTAssertTrue(VideoShrink.outputSize(width: 3840, height: 2160, quality: .hd1080) == (1920, 1080))
        XCTAssertTrue(VideoShrink.outputSize(width: 2160, height: 3840, quality: .hd1080) == (1080, 1920))
        XCTAssertTrue(VideoShrink.outputSize(width: 1280, height: 720, quality: .hd1080) == (1280, 720))
        XCTAssertTrue(VideoShrink.outputSize(width: 3840, height: 2160, quality: .sameQuality) == (3840, 2160))
    }

    func testEstimatesShrinkWithLowerResolutionAndTrimming() {
        let item = video()
        let full = VideoTrim.full(60)
        let same = VideoShrink.estimatedBytes(for: item, edit: VideoEdit(quality: .sameQuality, trim: full))
        let hd = VideoShrink.estimatedBytes(for: item, edit: VideoEdit(quality: .hd1080, trim: full))
        let hdHalf = VideoShrink.estimatedBytes(for: item, edit: VideoEdit(quality: .hd1080, trim: VideoTrim(start: 0, end: 30)))
        XCTAssertLessThan(same, item.currentBytes)
        XCTAssertLessThan(hd, same)
        XCTAssertEqual(Double(hdHalf), Double(hd) / 2, accuracy: 2)
    }

    func testEstimateNeverExceedsTheOriginalBitrate() {
        // Already a lean 1080p file: re-encoding can't promise anything, but trimming still can.
        let lean = video(width: 1920, height: 1080, bytes: 20_000_000)
        XCTAssertEqual(VideoShrink.estimatedBytes(for: lean, edit: VideoEdit(quality: .hd1080, trim: .full(60))), 20_000_000)
        XCTAssertEqual(VideoShrink.estimatedBytes(for: lean, edit: VideoEdit(quality: .hd1080, trim: VideoTrim(start: 0, end: 15))), 5_000_000)
    }

    func testTargetBitrateFollowsResolutionAndFrameRateButNeverExceedsTheSource() {
        let hd30 = VideoShrink.targetBitrate(width: 1920, height: 1080, frameRate: 30, sourceBitrate: 100_000_000)
        XCTAssertEqual(hd30, 4_354_560, accuracy: 1)
        XCTAssertEqual(VideoShrink.targetBitrate(width: 1920, height: 1080, frameRate: 60, sourceBitrate: 100_000_000), hd30 * 2, accuracy: 1)
        XCTAssertEqual(VideoShrink.targetBitrate(width: 1920, height: 1080, frameRate: 240, sourceBitrate: 100_000_000), hd30 * 2, accuracy: 1)
        XCTAssertEqual(VideoShrink.targetBitrate(width: 1920, height: 1080, frameRate: 30, sourceBitrate: 3_000_000), 3_000_000)
    }

    func testOnlyAClearSavingIsWorthReplacing() {
        XCTAssertTrue(VideoShrink.isWorthReplacing(originalBytes: 100, newBytes: 50))
        XCTAssertFalse(VideoShrink.isWorthReplacing(originalBytes: 100, newBytes: 97))
        XCTAssertFalse(VideoShrink.isWorthReplacing(originalBytes: 100, newBytes: 120))
        XCTAssertFalse(VideoShrink.isWorthReplacing(originalBytes: 100, newBytes: 0))
    }

    // MARK: Checks afterwards

    func testMatchingCopyKeepsEverything() {
        let edit = VideoEdit(quality: .hd1080, trim: VideoTrim(start: 5, end: 45))
        let result = VideoReplacement(
            originalID: "o", newID: "n", edit: edit, original: details(),
            new: details(date: referenceDate.addingTimeInterval(0.3), duration: 40.1, bytes: 60_000_000), originalGone: true
        )
        XCTAssertTrue(result.keptEverything)
        XCTAssertTrue(result.wasTrimmed)
        XCTAssertEqual(result.savedBytes, 280_000_000)
    }

    func testEachLostDetailIsCaught() {
        let edit = VideoEdit(quality: .sameQuality, trim: .full(60))
        func check(_ new: VideoDetails, gone: Bool = true) -> VideoReplacement {
            VideoReplacement(originalID: "o", newID: "n", edit: edit, original: details(), new: new, originalGone: gone)
        }
        let small: Int64 = 100_000_000
        XCTAssertTrue(check(details(bytes: small)).keptEverything)
        XCTAssertFalse(check(details(bytes: small)).wasTrimmed)
        XCTAssertFalse(check(details(date: referenceDate.addingTimeInterval(3600), bytes: small)).keptDate)
        XCTAssertFalse(check(details(lat: nil, bytes: small)).keptLocation)
        XCTAssertFalse(check(details(favorite: false, bytes: small)).keptFavorite)
        XCTAssertFalse(check(details(bytes: small, inAlbum: false)).keptAlbum)
        XCTAssertFalse(check(details(duration: 30, bytes: small)).rightLength)
        XCTAssertFalse(check(details(bytes: small, isVideo: false)).rightLength)
        XCTAssertFalse(check(details(bytes: 400_000_000)).isSmaller)
        XCTAssertFalse(check(details(bytes: 0)).isSmaller)
        XCTAssertFalse(check(details(bytes: small), gone: false).keptEverything)
    }

    // MARK: Mock library

    func testMockReplacesOnlyThePreparedVideo() async throws {
        let library = MockPhotoLibrary(items: [video(id: "v"), video(id: "other")])
        let edit = VideoEdit(quality: .hd1080, trim: VideoTrim(start: 10, end: 40))
        let prepared = try await library.prepareVideo("v", edit: edit)
        XCTAssertEqual(prepared.newDuration, 30)
        XCTAssertLessThan(prepared.newBytes, prepared.originalBytes)
        let changesBefore = await library.changeCount
        XCTAssertEqual(changesBefore, 0, "Preparing a copy changes nothing in the library")

        let result = try await library.replaceVideo(with: prepared)
        XCTAssertTrue(result.keptEverything)
        let ids = await library.items.map(\.id)
        XCTAssertEqual(Set(ids), ["other", "v-small"])
        let left = await library.preparedVideos
        XCTAssertTrue(left.isEmpty)
    }

    func testMockRefusesAVideoInAnotherAlbum() async {
        let library = MockPhotoLibrary(items: [video(id: "v")], inOtherAlbums: ["v"])
        do {
            _ = try await library.prepareVideo("v", edit: VideoEdit(quality: .hd1080, trim: .full(60)))
            XCTFail("Should refuse")
        } catch let error as PhotoChangeError {
            guard case .unsafe = error else { return XCTFail("Wrong error: \(error)") }
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testMockRefusesACopyThatIsntSmaller() async {
        let lean = video(id: "v", width: 1280, height: 720, bytes: 10_000_000)
        let library = MockPhotoLibrary(items: [lean])
        do {
            _ = try await library.prepareVideo("v", edit: VideoEdit(quality: .hd1080, trim: .full(60)))
            XCTFail("Should refuse")
        } catch {
            XCTAssertEqual(error as? PhotoChangeError, .videoNotSmaller)
        }
    }

    func testDecliningLeavesTheOriginal() async throws {
        let library = MockPhotoLibrary(items: [video(id: "v")])
        let prepared = try await library.prepareVideo("v", edit: VideoEdit(quality: .sameQuality, trim: .full(60)))
        await library.setDeclinesChanges(true)
        do {
            _ = try await library.replaceVideo(with: prepared)
            XCTFail("Should be cancelled")
        } catch {
            XCTAssertEqual(error as? PhotoChangeError, .cancelled)
        }
        let ids = await library.items.map(\.id)
        XCTAssertEqual(ids, ["v"])
    }
}
