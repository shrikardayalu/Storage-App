import XCTest
@testable import StorageCore

/// Step 7: most planted junk is found, and very few good photos are flagged.
final class JunkFinderTests: XCTestCase {
    private func photo(
        _ id: String,
        category: MediaCategory = .photo,
        bytes: Int64 = 3_000_000,
        minutes: Double = 0,
        width: Int = 4032,
        height: Int = 3024,
        burst: String? = nil
    ) -> MediaItem {
        MediaItem(
            id: id, category: category, format: category == .screenshot ? .png : .heic, filename: "\(id).HEIC",
            creationDate: referenceDate.addingTimeInterval(minutes * 60), pixelWidth: width, pixelHeight: height,
            duration: nil, originalBytes: bytes, thumbnailSeed: 1, burstID: burst
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
        _ print: [Float],
        sharpness: Double = 400,
        brightness: Double = 0.5,
        dark: Double = 0.02,
        lines: [String] = []
    ) -> PhotoSignals {
        PhotoSignals(featurePrint: print, sharpness: sharpness, brightness: brightness, darkFraction: dark, textLines: lines)
    }

    private let receipt = ["COFFEE HOUSE", "Latte 4.50", "Muffin 3.25", "Subtotal 7.75", "Tax 0.62", "TOTAL 8.37"]
    private let letter = ["Dear Sam,", "Thanks for the visit last week.", "The garden looks lovely", "now the roses are out.", "See you soon,", "Alex"]

    /// The planted test album: good photos, a copy, near-duplicates, junk, and things to leave alone.
    private func plantedAlbum() -> (items: [MediaItem], signals: [MediaItem.ID: PhotoSignals]) {
        let items = [
            photo("beach", minutes: 0),
            photo("dog", minutes: 30),
            photo("sunset", minutes: 90),
            photo("sky", minutes: 120),
            // An exact copy saved again later at lower resolution.
            photo("dog-copy", bytes: 900_000, minutes: 60 * 24 * 40, width: 2016, height: 1512),
            // Two near-identical beach shots seconds apart; the sharper one should be kept.
            photo("beach-2", minutes: 0.1),
            photo("beach-3", minutes: 0.2),
            photo("pocket", minutes: 200),
            photo("blur", minutes: 210),
            photo("receipt", minutes: 220),
            photo("letter", minutes: 230),
            photo("old-shot", category: .screenshot, bytes: 400_000, minutes: -60 * 24 * 90),
            photo("new-shot", category: .screenshot, bytes: 400_000, minutes: 0),
            // Burst shots are left to Step 5, even if blurry.
            photo("burst-a", burst: "B"),
            photo("burst-b", burst: "B"),
        ]
        let signals: [MediaItem.ID: PhotoSignals] = [
            "beach": signals(print(0), sharpness: 300),
            "beach-2": signals(print(0, nudge: 0.2), sharpness: 520),
            "beach-3": signals(print(0, nudge: 0.25), sharpness: 280),
            "dog": signals(print(1)),
            "dog-copy": signals(print(1, nudge: 0.01)),
            "sunset": signals(print(2), brightness: 0.25, dark: 0.3),
            // A clear blue sky: little detail, but sharp enough and not dark.
            "sky": signals(print(3), sharpness: 45, brightness: 0.7, dark: 0),
            "pocket": signals(print(4), sharpness: 3, brightness: 0.02, dark: 0.98),
            "blur": signals(print(5), sharpness: 12),
            "receipt": signals(print(6), lines: receipt),
            "letter": signals(print(7), lines: letter),
            "burst-a": signals(print(4), sharpness: 2),
            "burst-b": signals(print(4), sharpness: 2),
        ]
        return (items, signals)
    }

    private func report() -> JunkReport {
        let album = plantedAlbum()
        return JunkFinder.find(in: album.items, signals: album.signals, now: referenceDate)
    }

    // MARK: The step's test

    func testFindsPlantedJunkAndLeavesGoodPhotosAlone() {
        let report = report()
        let flagged = Set(report.findings.map(\.id))
            .union(report.duplicates.flatMap { $0.items.dropFirst() }.map(\.id))
        XCTAssertEqual(flagged, ["beach", "beach-3", "dog-copy", "pocket", "blur", "receipt", "letter", "old-shot"])
        for good in ["dog", "sunset", "sky", "new-shot", "beach-2", "burst-a", "burst-b"] {
            XCTAssertFalse(flagged.contains(good), "\(good) shouldn't be flagged")
        }
    }

    func testEachFindingHasTheRightReason() {
        let reasons = Dictionary(uniqueKeysWithValues: report().findings.map { ($0.id, $0.reason) })
        XCTAssertEqual(reasons, [
            "pocket": .dark, "blur": .blurry, "receipt": .receipt, "letter": .document, "old-shot": .oldScreenshot,
        ])
    }

    // MARK: Duplicates

    func testKeepsTheBestCopy() {
        let groups = report().duplicates
        XCTAssertEqual(groups.count, 2)
        let dog = groups.first { $0.items.contains { $0.id == "dog" } }!
        XCTAssertEqual(dog.suggestedKeeper, "dog", "more pixels wins")
        XCTAssertTrue(dog.isExact)
        let beach = groups.first { $0.items.contains { $0.id == "beach" } }!
        XCTAssertEqual(beach.suggestedKeeper, "beach-2", "the sharpest near-duplicate wins")
        XCTAssertFalse(beach.isExact)
        XCTAssertEqual(beach.savedBytes(keeping: "beach-2"), 6_000_000)
    }

    func testNearDuplicatesMustBeTakenCloseTogether() {
        let items = [photo("a", minutes: 0), photo("b", minutes: 60 * 5)]
        let signals = ["a": signals(print(0)), "b": signals(print(0, nudge: 0.2))]
        XCTAssertTrue(JunkFinder.find(in: items, signals: signals, now: referenceDate).duplicates.isEmpty)
    }

    func testDifferentShapesAreNotDuplicates() {
        let items = [photo("wide", width: 4032, height: 3024), photo("tall", width: 3024, height: 4032)]
        let signals = ["wide": signals(print(0)), "tall": signals(print(0))]
        XCTAssertTrue(JunkFinder.find(in: items, signals: signals, now: referenceDate).duplicates.isEmpty)
    }

    func testSimilarShotsDontChainIntoOneGroup() {
        // a~b and b~c are close, but a and c are not, so c can't join a's group.
        let items = [photo("a", minutes: 0), photo("b", minutes: 1), photo("c", minutes: 2)]
        let signals = [
            "a": signals(print(0)),
            "b": signals(print(0, nudge: 0.15)),
            "c": signals([0.94, 0.34, 0, 0, 0, 0, 0, 0].map { Float($0) }),
        ]
        let groups = JunkFinder.find(in: items, signals: signals, now: referenceDate).duplicates
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(Set(groups[0].items.map(\.id)), ["a", "b"])
    }

    func testVideosAreNeverFlagged() {
        let video = makeItem(id: "v", category: .video)
        let report = JunkFinder.find(in: [video], signals: ["v": signals(print(0), sharpness: 0, brightness: 0, dark: 1)], now: referenceDate)
        XCTAssertTrue(report.isEmpty)
    }

    // MARK: Validation

    func testRefusesRemovingEveryCopy() throws {
        let report = report()
        XCTAssertNoThrow(try report.validate(remove: ["beach", "beach-3", "blur"], keepers: ["beach-2"]))
        XCTAssertThrowsError(try report.validate(remove: ["beach", "beach-2", "beach-3"], keepers: []))
        XCTAssertThrowsError(try report.validate(remove: ["beach"], keepers: []), "a touched group needs a keeper")
        XCTAssertThrowsError(try report.validate(remove: ["beach-2"], keepers: ["beach-2"]))
    }

    // MARK: Measurements

    func testFlatGrayImageMeasuresAsNotSharp() {
        let flat = [UInt8](repeating: 128, count: 32 * 32)
        let stats = ImageStats.measure(gray: flat, width: 32, height: 32)
        XCTAssertEqual(stats.sharpness, 0, accuracy: 0.001)
        XCTAssertEqual(stats.brightness, 128.0 / 255, accuracy: 0.001)
        XCTAssertEqual(stats.darkFraction, 0)
    }

    func testCheckerboardMeasuresAsSharpAndBlackAsDark() {
        let checker = (0..<(32 * 32)).map { i in UInt8(((i % 32) + (i / 32)) % 2 == 0 ? 255 : 0) }
        XCTAssertGreaterThan(ImageStats.measure(gray: checker, width: 32, height: 32).sharpness, 10_000)
        let black = ImageStats.measure(gray: [UInt8](repeating: 3, count: 32 * 32), width: 32, height: 32)
        XCTAssertLessThan(black.brightness, 0.02)
        XCTAssertEqual(black.darkFraction, 1)
    }

    func testReceiptNeedsPricesAndAReceiptWord() {
        XCTAssertTrue(JunkFinder.isReceipt(receipt))
        XCTAssertFalse(JunkFinder.isReceipt(letter))
        XCTAssertFalse(JunkFinder.isReceipt(["Total war", "Chapter 2"]))
    }
}
