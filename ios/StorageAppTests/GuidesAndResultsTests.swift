import StorageCore
import XCTest
@testable import StorageApp

/// Other-app guides (Build Plan step 10) and the results screen (step 11),
/// run against mock services.
@MainActor
final class GuidesAndResultsTests: XCTestCase {
    /// Returns the next free-space reading on each call, then repeats the last one.
    private final class SteppingStorage: DeviceStorageService, @unchecked Sendable {
        private let lock = NSLock()
        private var readings: [Int64]

        init(_ readings: [Int64]) { self.readings = readings }

        func currentSnapshot() async throws -> StorageSnapshot {
            lock.withLock {
                let free = readings.count > 1 ? readings.removeFirst() : readings[0]
                return StorageSnapshot(date: Date(), totalBytes: 128_000_000_000, availableBytes: free, availableForImportantUsageBytes: free)
            }
        }
    }

    private func photo(_ id: String, bytes: Int64) -> MediaItem {
        MediaItem(id: id, category: .photo, format: .heic, filename: "\(id).HEIC", creationDate: Date(),
                  pixelWidth: 4032, pixelHeight: 3024, duration: nil, originalBytes: bytes, thumbnailSeed: 0)
    }

    // MARK: Guides

    func testEveryGuideHasDrawnStepsAndAWayIn() {
        for guide in OtherAppGuide.allCases {
            XCTAssertFalse(guide.steps.isEmpty, "\(guide)")
            XCTAssertTrue(guide.steps.allSatisfy { !$0.scene.isEmpty && !$0.title.isEmpty && !$0.note.isEmpty }, "\(guide)")
            XCTAssertEqual(guide.steps.first?.opens, true, "\(guide) starts with its Open button")
            XCTAssertNotNil(guide.destination.url, "\(guide)")
        }
        XCTAssertEqual(OtherAppGuide.whatsapp.destination.url?.scheme, "whatsapp")
    }

    func testSettingsPathsMatchTheRunningIOS() {
        let path = OtherAppGuide.settingsPath(for: "Safari")
        XCTAssertEqual(path.contains("Apps"), OtherAppGuide.appsInSettings)
    }

    func testGuideMeasuresFromWhenItOpened() async {
        // Opening reading, then two readings after the person cleared WhatsApp.
        let storage = SteppingStorage([5_000_000_000, 7_100_000_000])
        let model = AppModel(storage: storage)
        model.open(.whatsapp)
        await model.startMeasuring(.whatsapp)
        XCTAssertEqual(model.guideFreedBytes, 0)

        await model.checkGuide(readings: 2, every: .zero)
        XCTAssertEqual(model.guideFreedBytes, 2_100_000_000)

        model.closeOtherAppGuide()
        XCTAssertNil(model.otherAppGuide)
        XCTAssertEqual(model.freed.total(for: .guides), 2_100_000_000)
        XCTAssertEqual(model.freed.counted.first?.title, "WhatsApp")
    }

    func testGuideThatFreedNothingLeavesNoResult() async {
        let model = AppModel(storage: SteppingStorage([5_000_000_000, 5_004_000_000]))
        model.open(.safari)
        await model.startMeasuring(.safari)
        await model.checkGuide(readings: 2, every: .zero)
        model.closeOtherAppGuide()
        XCTAssertTrue(model.freed.entries.isEmpty, "4 MB is free space moving on its own")
    }

    // MARK: Results

    func testPhotoCleanupCountsOnceRecentlyDeletedIsEmptied() async {
        // Before the delete, after it (still in Recently Deleted), then emptied.
        let storage = SteppingStorage([5_000_000_000, 5_000_000_000, 5_000_000_000, 5_003_000_000])
        let library = MockPhotoLibrary(items: [photo("a", bytes: 3_000_000), photo("b", bytes: 1_000_000)])
        let model = AppModel(storage: storage, photoScanner: library, photoChanges: library)
        await model.scanTestAlbum()
        await model.delete(approved: ["a"])
        XCTAssertEqual(model.freed.total, 0)

        await model.checkReclaim(readings: 3, every: .zero)
        XCTAssertEqual(model.freed.total(for: .photos), 3_000_000)
        XCTAssertEqual(model.freed.counted.first?.title, "Deleted 1 item")
        XCTAssertEqual(model.freed.freeSpaceChange(now: model.deviceStorage!), model.freed.total)
    }

    func testResultsAreSavedAcrossLaunches() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("freed-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let model = AppModel(storage: SteppingStorage([5_000_000_000, 6_000_000_000]), freedStore: FreedLedgerStore(fileURL: url))
        model.open(.offloadApps)
        await model.startMeasuring(.offloadApps)
        await model.checkGuide(readings: 1, every: .zero)
        model.closeOtherAppGuide()

        let reloaded = AppModel(freedStore: FreedLedgerStore(fileURL: url))
        XCTAssertEqual(reloaded.freed.total, 1_000_000_000)

        reloaded.resetResults()
        XCTAssertTrue(FreedLedgerStore(fileURL: url).load().entries.isEmpty)
    }
    // MARK: Restart coach (Build Plan step 9)

    /// The time since the phone started, as the test sets it.
    private final class Uptime: @unchecked Sendable {
        var value: TimeInterval = 1_000_000
    }

    func testRestartIsMeasuredOnTheNextOpenAndCounted() async {
        let uptime = Uptime()
        let model = AppModel(storage: SteppingStorage([10_000_000_000, 10_000_000_000, 11_200_000_000]),
                             uptime: { uptime.value })
        await model.refreshDeviceStorage()
        XCTAssertEqual(model.storageWarning, nil)

        await model.startRestart()
        XCTAssertNotNil(model.restartCoach.pending)

        // The phone started after the baseline was taken.
        uptime.value = -120
        await model.refreshDeviceStorage()
        XCTAssertNil(model.restartCoach.pending)
        XCTAssertEqual(model.restartCoach.result?.gainedBytes, 1_200_000_000)
        XCTAssertEqual(model.freed.total(for: .restart), 1_200_000_000)

        model.dismissRestartResult()
        XCTAssertNil(model.restartCoach.result)
    }

    func testNoRestartMeansNothingIsCounted() async {
        let model = AppModel(storage: SteppingStorage([10_000_000_000, 10_000_000_000, 12_000_000_000]))
        await model.startRestart()
        await model.refreshDeviceStorage()
        XCTAssertNotNil(model.restartCoach.pending)
        XCTAssertNil(model.restartCoach.result)
        XCTAssertEqual(model.freed.total(for: .restart), 0)
    }

    func testLowSpaceSuggestsARestart() async {
        let model = AppModel(storage: SteppingStorage([2_000_000_000]))
        await model.refreshDeviceStorage()
        XCTAssertEqual(model.storageWarning, .low(availableBytes: 2_000_000_000))
    }
}
