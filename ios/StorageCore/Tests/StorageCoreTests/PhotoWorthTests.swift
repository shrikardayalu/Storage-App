import XCTest
@testable import StorageCore

/// Suggestions leave memories alone: sunsets, people, pets, favorites and
/// great shots aren't junk, and their Live Photos stay Live.
final class PhotoWorthTests: XCTestCase {
    private func photo(
        _ id: String,
        category: MediaCategory = .photo,
        bytes: Int64 = 3_000_000,
        minutes: Double = 0,
        width: Int = 4032,
        height: Int = 3024,
        traits: MediaTraits = []
    ) -> MediaItem {
        MediaItem(
            id: id, category: category, format: category == .screenshot ? .png : .heic, filename: "\(id).HEIC",
            creationDate: referenceDate.addingTimeInterval(minutes * 60), pixelWidth: width, pixelHeight: height,
            duration: nil, originalBytes: bytes, thumbnailSeed: 1, traits: traits,
            livePhotoVideoBytes: traits.contains(.livePhoto) ? 2_000_000 : 0
        )
    }

    /// A unit-length print pointing mostly along `axis`, nudged by `nudge` towards the next axis.
    private func print(_ axis: Int, nudge: Float = 0) -> [Float] {
        var v = [Float](repeating: 0, count: 8)
        v[axis] = (1 - nudge * nudge).squareRoot()
        v[(axis + 1) % 8] = nudge
        return v
    }

    private func signals(
        _ print: [Float] = [1, 0, 0, 0, 0, 0, 0, 0],
        sharpness: Double = 400,
        peak: Double? = nil,
        brightness: Double = 0.5,
        dark: Double = 0.02,
        faces: Int = 0,
        faceArea: Double = 0,
        faceQuality: Double? = nil,
        labels: [String: Double] = [:],
        aesthetics: Double? = nil,
        utility: Bool = false
    ) -> PhotoSignals {
        PhotoSignals(
            featurePrint: print, sharpness: sharpness, brightness: brightness, darkFraction: dark,
            peakSharpness: peak, faceCount: faces, faceArea: faceArea, faceQuality: faceQuality,
            labels: labels, aesthetics: aesthetics, isUtility: utility
        )
    }

    private func flagged(_ items: [MediaItem], _ signals: [MediaItem.ID: PhotoSignals]) -> [MediaItem.ID: JunkReason] {
        let report = JunkFinder.find(in: items, signals: signals, now: referenceDate)
        return Dictionary(uniqueKeysWithValues: report.findings.map { ($0.id, $0.reason) })
    }

    // MARK: Junk

    func testASoftSunsetIsNotBlurry() {
        let items = [photo("sunset"), photo("shaken", minutes: 30)]
        let found = flagged(items, [
            // Smooth sky: little detail overall, but Vision knows what it is.
            "sunset": signals(print(0), sharpness: 9, peak: 22, labels: ["sunset_sunrise": 0.86, "sky": 0.7]),
            "shaken": signals(print(1), sharpness: 9, peak: 22, labels: ["structure": 0.6]),
        ])
        XCTAssertEqual(found, ["shaken": .blurry])
    }

    func testOneCrispPartMeansNotBlurry() {
        let items = [photo("bokeh"), photo("mush", minutes: 30)]
        let found = flagged(items, [
            "bokeh": signals(print(0), sharpness: 18, peak: 240),
            "mush": signals(print(1), sharpness: 18, peak: 31),
        ])
        XCTAssertEqual(found, ["mush": .blurry])
    }

    func testAGoodLookingSoftPhotoIsNotBlurry() {
        let found = flagged([photo("fog"), photo("smear", minutes: 30)], [
            "fog": signals(print(0), sharpness: 10, peak: 20, aesthetics: 0.4),
            "smear": signals(print(1), sharpness: 10, peak: 20, aesthetics: -0.3),
        ])
        XCTAssertEqual(found, ["smear": .blurry])
    }

    func testPeoplePetsAndFavoritesAreNeverSoftOrDarkJunk() {
        let items = [
            photo("dance", minutes: 0), photo("concert", minutes: 30), photo("puppy", minutes: 60),
            photo("loved", minutes: 90, traits: .favorite), photo("cropped", minutes: 120, traits: .edited),
            photo("old-loved", category: .screenshot, minutes: -60 * 24 * 90, traits: .favorite),
            photo("pocket", minutes: 150),
        ]
        let found = flagged(items, [
            "dance": signals(print(0), sharpness: 8, peak: 15, faces: 2, faceArea: 0.05),
            "concert": signals(print(1), sharpness: 20, brightness: 0.03, dark: 0.95, labels: ["people": 0.7, "concert": 0.8]),
            "puppy": signals(print(2), sharpness: 11, peak: 30, labels: ["dog": 0.9]),
            "loved": signals(print(3), sharpness: 4, peak: 6),
            "cropped": signals(print(4), sharpness: 4, peak: 6),
            "pocket": signals(print(5), sharpness: 3, peak: 4, brightness: 0.02, dark: 0.98),
        ])
        XCTAssertEqual(found, ["pocket": .dark])
    }

    func testAPasserByInTheBackgroundDoesNotProtectAPhoto() {
        let found = flagged([photo("street")], ["street": signals(sharpness: 6, peak: 9, faces: 1, faceArea: 0.0006)])
        XCTAssertEqual(found, ["street": .blurry])
    }

    func testWeakLabelsDontCount() {
        let found = flagged([photo("wall")], ["wall": signals(sharpness: 6, peak: 9, labels: ["sky": 0.12, "people": 0.2])])
        XCTAssertEqual(found, ["wall": .blurry])
    }

    // MARK: Duplicates

    func testTwoTakesOfASunsetAreNotDuplicatesButTheSameFrameIs() {
        let scenic: [String: Double] = ["sunset_sunrise": 0.9]
        let items = [photo("take-1", minutes: 0), photo("take-2", minutes: 1), photo("take-2-again", minutes: 1.05)]
        let report = JunkFinder.find(in: items, signals: [
            "take-1": signals(print(0), labels: scenic),
            // Close enough to pair two plain photos, not two keepers.
            "take-2": signals(print(0, nudge: 0.26), labels: scenic),
            "take-2-again": signals(print(0, nudge: 0.3), labels: scenic),
        ], now: referenceDate)
        XCTAssertEqual(report.duplicates.count, 1)
        XCTAssertEqual(Set(report.duplicates[0].items.map(\.id)), ["take-2", "take-2-again"])
    }

    func testPlainNearDuplicatesStillPair() {
        let items = [photo("desk-1", minutes: 0), photo("desk-2", minutes: 1)]
        let report = JunkFinder.find(in: items, signals: [
            "desk-1": signals(print(0)), "desk-2": signals(print(0, nudge: 0.26)),
        ], now: referenceDate)
        XCTAssertEqual(report.duplicates.count, 1)
    }

    func testAFavoriteIsTheCopyKeptAndNeverAnExtra() {
        let items = [
            photo("big", minutes: 0),
            photo("small-favorite", bytes: 900_000, minutes: 1, width: 2016, height: 1512, traits: .favorite),
            photo("other-favorite", minutes: 2, traits: .favorite),
        ]
        let same = signals(print(0))
        let report = JunkFinder.find(in: items, signals: ["big": same, "small-favorite": same, "other-favorite": same], now: referenceDate)
        let group = try? XCTUnwrap(report.duplicates.first)
        XCTAssertEqual(group?.suggestedKeeper, "other-favorite")
        XCTAssertEqual(group.map { Set($0.items.map(\.id)) }, ["other-favorite", "big"])
    }

    func testBetterFacesWinBetweenNearDuplicates() {
        let items = [photo("blink", minutes: 0), photo("smile", minutes: 0.1)]
        let report = JunkFinder.find(in: items, signals: [
            "blink": signals(print(0), sharpness: 600, faces: 1, faceArea: 0.1, faceQuality: 0.3),
            "smile": signals(print(0, nudge: 0.1), sharpness: 500, faces: 1, faceArea: 0.1, faceQuality: 0.8),
        ], now: referenceDate)
        XCTAssertEqual(report.duplicates.first?.suggestedKeeper, "smile")
    }

    // MARK: Live Photos

    func testLivePhotosOfThingsBecomeStillsAndMemoriesStayLive() {
        let live: MediaTraits = .livePhoto
        let items = [
            photo("lunch", traits: live), photo("sign", traits: live), photo("kids", traits: live),
            photo("cat", traits: live), photo("coast", traits: live), photo("dull-sky", traits: live),
            photo("wow", traits: live), photo("label", traits: live), photo("starred", traits: [.livePhoto, .favorite]),
            photo("tuned", traits: [.livePhoto, .edited]), photo("unseen", traits: live),
        ]
        let reasons = LiveStills.keepReasons(for: items, signals: [
            "lunch": signals(labels: ["food": 0.9], aesthetics: 0.3),
            "sign": signals(labels: ["text": 0.8], utility: true),
            "kids": signals(faces: 2, faceArea: 0.08),
            "cat": signals(labels: ["cat": 0.8]),
            "coast": signals(labels: ["ocean": 0.7, "beach": 0.6], aesthetics: 0.35),
            // Scenery Vision rates as a poor shot isn't a "cool landscape".
            "dull-sky": signals(labels: ["sky": 0.8], aesthetics: -0.25),
            "wow": signals(labels: ["architecture": 0.6], aesthetics: 0.7),
            // A practical picture stays practical however tidy it looks.
            "label": signals(labels: ["sky": 0.5], aesthetics: 0.7, utility: true),
            "starred": signals(labels: ["food": 0.9]),
            "tuned": signals(labels: ["food": 0.9]),
        ])
        XCTAssertEqual(reasons, [
            "kids": .people, "cat": .animals, "coast": .scenic, "wow": .striking,
            "starred": .favorite, "unseen": .notChecked,
        ])
    }

    func testSceneryCountsOnPhonesThatCantScoreLooks() {
        let item = photo("coast", traits: .livePhoto)
        XCTAssertEqual(LiveStills.keepReason(for: item, signals: signals(labels: ["mountain": 0.6])), .scenic)
    }

    // MARK: Measurements

    func testPeakSharpnessFindsACrispCornerInASmoothPicture() {
        let side = 64
        // Flat gray, with a checkerboard in the top-left quarter.
        let patch = (0..<(side * side)).map { i -> UInt8 in
            let (x, y) = (i % side, i / side)
            return x < side / 2 && y < side / 2 ? (((x + y) % 2 == 0) ? 255 : 0) : 128
        }
        let stats = ImageStats.measure(gray: patch, width: side, height: side)
        XCTAssertGreaterThan(stats.peakSharpness, 10_000)
        XCTAssertGreaterThan(stats.peakSharpness, stats.sharpness)

        let flat = ImageStats.measure(gray: [UInt8](repeating: 128, count: side * side), width: side, height: side)
        XCTAssertEqual(flat.peakSharpness, 0, accuracy: 0.001)
    }

    func testOneBrightDotIsNotACrispPart() {
        let side = 64
        var gray = [UInt8](repeating: 40, count: side * side)
        gray[5 * side + 5] = 255
        let stats = ImageStats.measure(gray: gray, width: side, height: side)
        XCTAssertEqual(stats.peakSharpness, 0, accuracy: 0.001)
    }

    // MARK: Saved measurements

    func testNewMeasurementsAreSavedAndOldFilesLoadAsOutOfDate() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("signals-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = PhotoSignalsStore(fileURL: url)

        // A record as the first version saved it: no version, none of the newer fields.
        struct OldRecord: Codable {
            var id = "old"
            var print = Data([0x7F, 0xFF, 0, 0])
            var sharpness = 120.0
            var brightness = 0.4
            var darkFraction = 0.1
            var textLines: [String] = []
            var textCoverage = 0.0
        }
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let body = try encoder.encode([OldRecord()])
        var block = Data()
        for shift in [24, 16, 8, 0] { block.append(UInt8(truncatingIfNeeded: body.count >> shift)) }
        block.append(body)
        try block.write(to: url)

        store.append(["new": signals(peak: 88, faces: 2, faceArea: 0.07, faceQuality: 0.6, labels: ["dog": 0.9], aesthetics: 0.42, utility: true)])
        let loaded = store.load()

        let old = try XCTUnwrap(loaded["old"])
        XCTAssertEqual(old.version, 1)
        XCTAssertLessThan(old.version, PhotoSignals.currentVersion)
        XCTAssertEqual(old.sharpness, 120)
        XCTAssertNil(old.peakSharpness)

        let new = try XCTUnwrap(loaded["new"])
        XCTAssertEqual(new.version, PhotoSignals.currentVersion)
        XCTAssertEqual(new.peakSharpness, 88)
        XCTAssertEqual(new.faceCount, 2)
        XCTAssertEqual(new.faceQuality, 0.6)
        XCTAssertEqual(new.labels, ["dog": 0.9])
        XCTAssertEqual(new.aesthetics, 0.42)
        XCTAssertTrue(new.isUtility)
    }
}
