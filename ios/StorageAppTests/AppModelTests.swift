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

    // MARK: Library scan

    func testScanGroupsTheLibrary() async {
        let items = [
            MediaItem(id: "a", category: .photo, format: .heic, filename: "a.HEIC", creationDate: Date(),
                      pixelWidth: 4032, pixelHeight: 3024, duration: nil, originalBytes: 3_000_000, thumbnailSeed: 0),
            MediaItem(id: "b", category: .video, format: .hevc, filename: "b.MOV", creationDate: Date(),
                      pixelWidth: 3840, pixelHeight: 2160, duration: 60, originalBytes: 400_000_000, thumbnailSeed: 0),
        ]
        let model = AppModel(photoScanner: MockPhotoScanService(items: items))
        await model.scanLibrary()
        XCTAssertNil(model.scanError)
        XCTAssertEqual(model.libraryScan?.total.count, 2)
        XCTAssertEqual(model.libraryScan?.items.first?.id, "b")
        XCTAssertEqual(model.libraryScan?[.bigFormats].count, 1)
    }

    func testScanReportsDeniedAccess() async {
        let denied = AppModel(photoScanner: MockPhotoScanService(items: [], access: .denied))
        await denied.scanLibrary()
        XCTAssertEqual(denied.scanError, .accessDenied)
    }

    func testScanIfAllowedNeverPrompts() async {
        let model = AppModel(photoScanner: MockPhotoScanService(items: [], access: .notDetermined))
        await model.scanIfAllowed()
        XCTAssertNil(model.libraryScan)
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
        await model.scanLibrary()
        model.toggleSelection("a")
        model.toggleSelection("b")

        // Only "a" is still on the receipt when Delete is tapped.
        let error = await model.delete(approved: ["a"])
        XCTAssertNil(error)
        let remaining = await library.items.map(\.id)
        XCTAssertEqual(Set(remaining), ["b", "c"])
        XCTAssertEqual(Set(model.libraryScan?.items.map(\.id) ?? []), ["b", "c"])
        XCTAssertFalse(model.selection.contains("a"))
        guard case .deleted(let receipt)? = model.guide?.kind else { return XCTFail("No guide") }
        XCTAssertTrue(receipt.onlyApprovedRemoved)
        XCTAssertEqual(model.reclaim?.expectedBytes, 1_000_000)
    }

    /// Returns the next free-space reading on each call, then repeats the last one.
    private final class SteppingStorage: DeviceStorageService, @unchecked Sendable {
        private let lock = NSLock()
        private var readings: [Int64]
        private(set) var reads = 0

        init(_ readings: [Int64]) { self.readings = readings }

        func currentSnapshot() async throws -> StorageSnapshot {
            lock.withLock {
                reads += 1
                let free = readings.count > 1 ? readings.removeFirst() : readings[0]
                return StorageSnapshot(date: Date(), totalBytes: 128_000_000_000, availableBytes: free, availableForImportantUsageBytes: free)
            }
        }
    }

    func testMeasureAgainKeepsReadingUntilTheSpaceIsBack() async {
        // Baseline, then two readings before iOS counts the emptied space.
        let storage = SteppingStorage([5_000_000_000, 5_000_000_000, 5_000_000_000, 5_001_000_000])
        let library = MockPhotoLibrary(items: [item("a"), item("b")])
        let model = AppModel(storage: storage, photoScanner: library, photoChanges: library)
        await model.scanLibrary()
        await model.delete(approved: ["a"])

        await model.checkReclaim(readings: 6, every: .zero)
        XCTAssertEqual(model.reclaim?.isDone, true)
        XCTAssertEqual(model.lastReclaimCheck?.gainedBytes, 1_000_000)
        XCTAssertEqual(storage.reads, 4, "Stops reading once the space is back")
        XCTAssertFalse(model.isCheckingReclaim)
    }

    func testMeasureAgainReportsNoChange() async {
        let storage = SteppingStorage([5_000_000_000])
        let library = MockPhotoLibrary(items: [item("a"), item("b")])
        let model = AppModel(storage: storage, photoScanner: library, photoChanges: library)
        await model.scanLibrary()
        await model.delete(approved: ["a"])

        await model.checkReclaim(readings: 3, every: .zero)
        XCTAssertEqual(model.reclaim?.isDone, false)
        XCTAssertEqual(model.lastReclaimCheck?.gainedBytes, 0)
        XCTAssertEqual(storage.reads, 4)
        XCTAssertEqual(model.spaceWaiting, 1_000_000)
    }

    func testNothingOutsideTheScanCanBeSelected() async {
        let model = AppModel(library: MockPhotoLibrary(items: [item("a")]))
        await model.scanLibrary()
        model.toggleSelection("someone-elses-photo")
        XCTAssertTrue(model.selection.isEmpty)
    }

    func testUnsafeDeleteChangesNothing() async {
        let library = MockPhotoLibrary(items: [item("a"), item("b")])
        let model = AppModel(library: library)
        await model.scanLibrary()

        // "gone" left the library after the review screen was shown.
        let error = await model.delete(approved: ["a", "gone"])
        guard case .unsafe? = error else { return XCTFail("Expected the safety check to block it") }
        let count = await library.items.count
        XCTAssertEqual(count, 2)
        XCTAssertNil(model.guide)
    }

    func testGuideWaitsForReviewSheetToClose() async {
        let model = AppModel(library: MockPhotoLibrary(items: [item("a")]))
        await model.scanLibrary()
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
        await model.scanLibrary()
        XCTAssertEqual(model.convertibleLivePhotos.map(\.id), ["live"])

        let error = await model.convertToStills(approved: ["live"])
        XCTAssertNil(error)
        XCTAssertTrue(model.convertibleLivePhotos.isEmpty)
        XCTAssertEqual(model.libraryScan?.total.count, 2)
        guard case .convertedLivePhotos(let results)? = model.guide?.kind else { return XCTFail("No guide") }
        XCTAssertTrue(results.allSatisfy(\.keptEverything))
        XCTAssertEqual(model.guide?.expectedBytes, 3_000_000)
    }

    // MARK: Screenshot re-save

    func testResavingScreenshotsReplacesThePNGs() async {
        func shot(_ id: String, _ format: MediaFormat) -> MediaItem {
            MediaItem(id: id, category: .screenshot, format: format, filename: "\(id).\(format.fileExtension)",
                      creationDate: Date(), pixelWidth: 1179, pixelHeight: 2556, duration: nil,
                      originalBytes: 2_000_000, thumbnailSeed: 1)
        }
        let library = MockPhotoLibrary(items: [shot("png", .png), shot("heic", .heic)])
        let model = AppModel(library: library)
        await model.scanLibrary()
        XCTAssertEqual(model.resavableScreenshots.map(\.id), ["png"])
        XCTAssertEqual(model.screenshotSaving, 1_300_000)

        let error = await model.resaveScreenshots(approved: ["png"])
        XCTAssertNil(error)
        XCTAssertTrue(model.resavableScreenshots.isEmpty)
        XCTAssertEqual(model.libraryScan?.total.count, 2)
        guard case .resavedScreenshots(let receipt)? = model.guide?.kind else { return XCTFail("No guide") }
        XCTAssertTrue(receipt.resaved.allSatisfy(\.keptEverything))
        XCTAssertEqual(model.guide?.expectedBytes, 1_300_000)
    }

    // MARK: Bursts (Build Plan step 5)

    func testKeepingBurstPicksLeavesOneShotPerBurst() async {
        func shot(_ id: String, _ burst: String) -> MediaItem {
            MediaItem(id: id, category: .photo, format: .heic, filename: "\(id).HEIC", creationDate: Date(),
                      pixelWidth: 4032, pixelHeight: 3024, duration: nil, originalBytes: 1_000_000, thumbnailSeed: 0,
                      burstID: burst)
        }
        let library = MockPhotoLibrary(items: [shot("a1", "A"), shot("a2", "A"), shot("a3", "A"), shot("b1", "B"), shot("b2", "B"), item("plain")])
        let model = AppModel(library: library)
        await model.scanLibrary()
        XCTAssertEqual(model.bursts.count, 2)

        let error = await model.keepBurstPicks(["A": "a1", "B": "b2"])
        XCTAssertNil(error)
        XCTAssertTrue(model.bursts.isEmpty)
        XCTAssertEqual(Set(model.libraryScan?.items.map(\.id) ?? []), ["a1", "b2", "plain"])
        guard case .keptBurstPicks(let receipt)? = model.guide?.kind else { return XCTFail("No guide") }
        XCTAssertTrue(receipt.isExact)
        XCTAssertEqual(model.guide?.expectedBytes, 3_000_000)
    }

    // MARK: Videos (Build Plan step 6)

    func testShrinkingAVideoSwapsInTheCopyAndOpensTheGuide() async {
        let video = MediaItem(id: "v", category: .video, format: .h264, filename: "IMG_9.MOV", creationDate: Date(),
                              pixelWidth: 3840, pixelHeight: 2160, duration: 60, originalBytes: 340_000_000, thumbnailSeed: 0)
        let library = MockPhotoLibrary(items: [video, item("plain")])
        let model = AppModel(library: library)
        await model.scanLibrary()
        XCTAssertEqual(model.shrinkableVideos.map(\.id), ["v"])

        let edit = VideoEdit(quality: .smaller, trim: VideoTrim(start: 5, end: 35))
        guard case .success(let prepared) = await model.prepareVideo("v", edit: edit) else { return XCTFail("No copy") }
        XCTAssertNil(model.guide, "Making a copy changes nothing")

        let error = await model.replaceVideo(with: prepared)
        XCTAssertNil(error)
        XCTAssertEqual(Set(model.libraryScan?.items.map(\.id) ?? []), ["v-small", "plain"])
        guard case .shrunkVideo(let result)? = model.guide?.kind else { return XCTFail("No guide") }
        XCTAssertTrue(result.keptEverything)
        XCTAssertTrue(result.wasTrimmed)
        XCTAssertEqual(model.guide?.expectedBytes, 340_000_000)
    }

    func testShrinkingAllVideosSwapsThemInOneChange() async {
        func video(_ id: String, bytes: Int64) -> MediaItem {
            MediaItem(id: id, category: .video, format: .h264, filename: "IMG_\(id).MOV", creationDate: Date(),
                      pixelWidth: 3840, pixelHeight: 2160, duration: 60, originalBytes: bytes, thumbnailSeed: 0)
        }
        // "lean" is already below what the copy would be, so it's left alone.
        let library = MockPhotoLibrary(items: [video("a", bytes: 340_000_000), video("b", bytes: 200_000_000),
                                               video("lean", bytes: 20_000_000), item("plain")])
        let model = AppModel(library: library)
        await model.scanLibrary()

        let error = await model.shrinkVideos(["a": .smaller, "b": .sameQuality, "lean": .sameQuality])
        XCTAssertNil(error)
        let changes = await library.changeCount
        XCTAssertEqual(changes, 1, "One Photos change, so iOS asks once")
        XCTAssertEqual(Set(model.libraryScan?.items.map(\.id) ?? []), ["a-small", "b-small", "lean", "plain"])
        guard case .shrunkVideos(let results, let skipped)? = model.guide?.kind else { return XCTFail("No guide") }
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(skipped, 1)
        XCTAssertTrue(results.allSatisfy(\.keptEverything))
        // Copies are made after the baseline, so only the saving can come back.
        XCTAssertEqual(model.guide?.expectedBytes, results.reduce(Int64(0)) { $0 + $1.savedBytes })
        XCTAssertGreaterThan(model.guide?.expectedBytes ?? 0, 0)
        XCTAssertNil(model.videoBatchProgress)
    }

    // MARK: Duplicates + junk (Build Plan step 7)

    private func junkLibrary() -> (MockPhotoLibrary, MockPhotoAnalysis) {
        let items = [item("dog", bytes: 3_000_000), item("dog-copy", bytes: 900_000), item("blur"), item("good")]
        func signals(_ axis: Int, sharpness: Double = 400) -> PhotoSignals {
            var print = [Float](repeating: 0, count: 4)
            print[axis] = 1
            return PhotoSignals(featurePrint: print, sharpness: sharpness, brightness: 0.5, darkFraction: 0)
        }
        let analysis = MockPhotoAnalysis(signals: [
            "dog": signals(0), "dog-copy": signals(0), "blur": signals(1, sharpness: 5), "good": signals(2),
        ])
        return (MockPhotoLibrary(items: items), analysis)
    }

    func testMeasurementsAreSavedAndNotMadeTwice() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("signals-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = PhotoSignalsStore(fileURL: url)
        let (library, analysis) = junkLibrary()

        let first = AppModel(photoScanner: library, photoChanges: library, photoAnalyzer: analysis, signalsStore: store)
        await first.scanLibrary()
        await first.findJunk()
        XCTAssertTrue(first.junkAnalysisFinished)
        XCTAssertEqual(Set(store.load().keys), ["dog", "dog-copy", "blur", "good"])

        // A later launch with an analyzer that can't measure anything still
        // finds the same junk, from what was saved.
        let second = AppModel(photoScanner: library, photoChanges: library, photoAnalyzer: MockPhotoAnalysis(), signalsStore: store)
        await second.scanLibrary()
        await second.findJunk()
        XCTAssertEqual(second.junkReport?.duplicates.count, 1)
        XCTAssertEqual(second.junkReport?.findings.map(\.id), ["blur"])
        XCTAssertFalse(second.isAnalyzing)
    }

    func testFindingJunkFlagsCopiesAndBlurButNotGoodPhotos() async {
        let (library, analysis) = junkLibrary()
        let model = AppModel(library: library, analysis: analysis)
        await model.scanLibrary()
        await model.findJunk()
        let report = model.junkReport
        XCTAssertEqual(report?.duplicates.count, 1)
        XCTAssertEqual(report?.findings.map(\.id), ["blur"])
        XCTAssertEqual(report?.suggestedCount, 2)
        let count = await library.changeCount
        XCTAssertEqual(count, 0, "finding never changes anything")
    }

    func testRemovingJunkKeepsThePickedCopy() async {
        let (library, analysis) = junkLibrary()
        let model = AppModel(library: library, analysis: analysis)
        await model.scanLibrary()
        await model.findJunk()
        let keeper = model.junkReport!.duplicates[0].suggestedKeeper

        // Removing every copy is refused before anything changes.
        let refused = await model.removeJunk(["dog", "dog-copy"], keeping: [])
        guard case .junkChanged? = refused else { return XCTFail("Expected a refusal") }
        let unchanged = await library.changeCount
        XCTAssertEqual(unchanged, 0)

        let error = await model.removeJunk(["dog-copy", "blur"], keeping: [keeper])
        XCTAssertNil(error)
        XCTAssertEqual(Set(model.libraryScan?.items.map(\.id) ?? []), ["dog", "good"])
        XCTAssertEqual(model.junkReport?.isEmpty, true)
        guard case .deleted(let receipt)? = model.guide?.kind else { return XCTFail("No guide") }
        XCTAssertTrue(receipt.onlyApprovedRemoved)
    }

    func testOneTapPhotoCleanupRemovesJunkAndMakesStillsWithOneGuide() async throws {
        let items = [item("dog", bytes: 3_000_000), item("dog-copy", bytes: 900_000), item("blur"), item("live", bytes: 5_000_000, live: 3_000_000)]
        func signals(_ axis: Int, sharpness: Double = 400) -> PhotoSignals {
            var print = [Float](repeating: 0, count: 4)
            print[axis] = 1
            return PhotoSignals(featurePrint: print, sharpness: sharpness, brightness: 0.5, darkFraction: 0)
        }
        let analysis = MockPhotoAnalysis(signals: [
            "dog": signals(0), "dog-copy": signals(0), "blur": signals(1, sharpness: 5), "live": signals(2),
        ])
        let model = AppModel(library: MockPhotoLibrary(items: items), analysis: analysis)
        await model.scanLibrary()
        await model.findJunk()

        let plan = try XCTUnwrap(model.photoCleanupPlan)
        XCTAssertEqual(plan.remove, ["dog-copy", "blur"])
        XCTAssertEqual(plan.keepers, ["dog"])
        XCTAssertEqual(plan.convert, ["live"])
        XCTAssertEqual(plan.totalBytes, 900_000 + 1_000_000 + 3_000_000)
        XCTAssertEqual(model.saving(for: .photoCleanup), plan.totalBytes)

        let error = await model.cleanUpPhotos(plan)
        XCTAssertNil(error)
        XCTAssertEqual(model.libraryScan?.total.count, 2)
        XCTAssertTrue(model.convertibleLivePhotos.isEmpty)
        XCTAssertEqual(model.photoCleanupPlan?.isEmpty, true)
        guard case .photoCleanup(let receipt, let stills)? = model.guide?.kind else { return XCTFail("No guide") }
        XCTAssertEqual(receipt?.deleted, ["dog-copy", "blur"])
        XCTAssertEqual(stills.count, 1)
        XCTAssertEqual(model.guide?.expectedBytes, plan.totalBytes)
    }

    func testOnlyLivePhotosThatDontNeedToBeLiveAreSuggested() async {
        let items = [
            item("lunch", bytes: 5_000_000, live: 3_000_000),
            item("kids", bytes: 5_000_000, live: 3_000_000),
            item("unseen", bytes: 5_000_000, live: 3_000_000),
        ]
        func signals(_ axis: Int, faces: Int = 0) -> PhotoSignals {
            var print = [Float](repeating: 0, count: 4)
            print[axis] = 1
            return PhotoSignals(featurePrint: print, sharpness: 400, brightness: 0.5, darkFraction: 0,
                                faceCount: faces, faceArea: faces > 0 ? 0.1 : 0)
        }
        let analysis = MockPhotoAnalysis(signals: ["lunch": signals(0), "kids": signals(1, faces: 2)])
        let model = AppModel(library: MockPhotoLibrary(items: items), analysis: analysis)
        await model.scanLibrary()
        // Before the photos are checked, the figure covers every Live Photo.
        XCTAssertNil(model.suggestedLivePhotos)
        XCTAssertEqual(model.saving(for: .livePhotos), 9_000_000)

        await model.findJunk()
        XCTAssertEqual(model.suggestedLivePhotos?.map(\.id), ["lunch"])
        XCTAssertEqual(model.liveKeepReasons, ["kids": .people, "unseen": .notChecked])
        XCTAssertTrue(model.liveCheckFinished, "every Live Photo was looked at, including the one with no measurement")
        XCTAssertEqual(model.liveAnalysisProgress, 1)
        XCTAssertEqual(model.photoCleanupPlan?.convert, ["lunch"])
        XCTAssertEqual(model.saving(for: .livePhotos), 3_000_000)
        // Every Live Photo can still be picked by hand.
        XCTAssertEqual(model.convertibleLivePhotos.count, 3)
    }

    func testLivePhotosAreMeasuredFirstAndAFinishedPassIsNotRunAgain() async {
        let analysis = RecordingAnalysis()
        let library = MockPhotoLibrary(items: [
            item("plain", bytes: 9_000_000),
            item("live", bytes: 1_000_000, live: 500_000),
        ])
        let model = AppModel(photoScanner: library, photoChanges: library, photoAnalyzer: analysis)
        await model.scanLibrary()
        // Before the pass, the saving is already the Live Photo's video, not a blank.
        XCTAssertNil(model.suggestedLivePhotos)
        XCTAssertEqual(model.saving(for: .livePhotos), 500_000)

        await model.findJunk()
        XCTAssertEqual(analysis.batches.first?.first, "live", "Live Photos are measured before the rest of the library")
        XCTAssertTrue(model.liveCheckFinished)
        XCTAssertFalse(model.isAnalyzing)
        XCTAssertNotNil(model.junkReport)
        XCTAssertNotNil(model.saving(for: .duplicates))

        let calls = analysis.batches.count
        await model.findJunk()
        XCTAssertEqual(analysis.batches.count, calls, "opening the tool again must not restart the scan")
        XCTAssertFalse(model.isAnalyzing)
    }

    func testMeasurementsFromAnOlderVersionAreMadeAgain() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("signals-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = PhotoSignalsStore(fileURL: url)
        // What the first version knew: a soft photo, so it called it blurry.
        store.append(["sunset": PhotoSignals(featurePrint: [1, 0, 0, 0], sharpness: 5, brightness: 0.4, darkFraction: 0.1, version: 1)])
        let analysis = MockPhotoAnalysis(signals: [
            "sunset": PhotoSignals(featurePrint: [1, 0, 0, 0], sharpness: 5, brightness: 0.4, darkFraction: 0.1,
                                   peakSharpness: 20, labels: ["sunset_sunrise": 0.9]),
        ])
        let library = MockPhotoLibrary(items: [item("sunset")])
        let model = AppModel(photoScanner: library, photoChanges: library, photoAnalyzer: analysis, signalsStore: store)
        await model.scanLibrary()
        await model.findJunk()

        XCTAssertEqual(model.junkReport?.isEmpty, true, "a sunset isn't junk once Vision has seen it")
        XCTAssertEqual(store.load()["sunset"]?.version, PhotoSignals.currentVersion)
    }

    // MARK: Files cleanup (Build Plan step 8)

    func testFilesCleanupDeletesOnlyApprovedFilesInThePickedFolder() async {
        let now = Date()
        let folder = MockFolderFiles(files: [
            FileItem(path: "Holiday.mov", bytes: 400_000_000, modified: now),
            FileItem(path: "Report.pdf", bytes: 4_000_000, modified: now.addingTimeInterval(-86_400), contentHash: "a"),
            FileItem(path: "Report copy.pdf", bytes: 4_000_000, modified: now, contentHash: "a"),
            FileItem(path: "Notes.txt", bytes: 1_000, modified: now),
        ], outsideFiles: [FileItem(path: "Elsewhere.mov", bytes: 900_000_000, modified: now)])
        let model = AppModel(library: MockPhotoLibrary(items: []), folder: folder)
        await model.pick(folder: URL(fileURLWithPath: "/mock/Storage App Test"))
        XCTAssertEqual(model.fileReport?.large.map(\.id), ["Holiday.mov"])
        XCTAssertEqual(model.fileReport?.duplicates.first?.suggestedKeeper, "Report.pdf")

        let scan = model.folderScan!
        let error = await model.deleteFiles([scan["Holiday.mov"]!, scan["Report copy.pdf"]!], keeping: [scan["Report.pdf"]!])
        XCTAssertNil(error)
        XCTAssertEqual(model.lastFileDeletion?.isExact, true)
        XCTAssertEqual(Set(model.folderScan?.files.map(\.id) ?? []), ["Report.pdf", "Notes.txt"])
        let outside = await folder.outsideFiles.count
        XCTAssertEqual(outside, 1)
    }

    func testFilesCleanupRefusesDeletingEveryCopy() async {
        let now = Date()
        let folder = MockFolderFiles(files: [
            FileItem(path: "a.pdf", bytes: 1_000, modified: now, contentHash: "x"),
            FileItem(path: "b.pdf", bytes: 1_000, modified: now, contentHash: "x"),
        ])
        let model = AppModel(library: MockPhotoLibrary(items: []), folder: folder)
        await model.pick(folder: URL(fileURLWithPath: "/mock/F"))
        let error = await model.deleteFiles(model.folderScan!.files, keeping: [])
        guard case .changed? = error else { return XCTFail("Expected a refusal") }
        let count = await folder.deleteCount
        XCTAssertEqual(count, 0)
    }
}

/// Records the order photos are handed to the analyzer.
private final class RecordingAnalysis: PhotoAnalysisService, @unchecked Sendable {
    var batches: [[MediaItem.ID]] = []

    func analyze(_ items: [MediaItem], progress: @escaping @Sendable (Double) -> Void) async -> [MediaItem.ID: PhotoSignals] {
        batches.append(items.map(\.id))
        progress(1)
        return [:]
    }
}
