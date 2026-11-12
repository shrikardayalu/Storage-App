import XCTest
@testable import StorageCore

/// Photo measurements are saved between launches, so a big library is only measured once.
final class PhotoSignalsStoreTests: XCTestCase {
    private var url: URL!

    override func setUp() {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("signals-\(UUID().uuidString).bin")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: url)
    }

    private func signals(_ seed: Float, lines: [String] = []) -> PhotoSignals {
        // A unit-length print, as the analyzer makes them.
        let raw = (0..<768).map { Float($0 % 7) * 0.1 + seed }
        let length = raw.reduce(0) { $0 + $1 * $1 }.squareRoot()
        return PhotoSignals(
            featurePrint: raw.map { $0 / length }, sharpness: Double(seed) * 100, brightness: 0.4,
            darkFraction: 0.1, textLines: lines, textCoverage: 0.2
        )
    }

    func testNothingSavedLoadsEmpty() {
        XCTAssertTrue(PhotoSignalsStore(fileURL: url).load().isEmpty)
        XCTAssertTrue(PhotoSignalsStore.inMemory.load().isEmpty)
    }

    func testAppendedBlocksAllLoadAndLaterOnesWin() {
        let store = PhotoSignalsStore(fileURL: url)
        store.append(["a": signals(1), "b": signals(2, lines: ["TOTAL 8.37"])])
        store.append(["c": signals(3), "a": signals(4)])

        let loaded = store.load()
        XCTAssertEqual(Set(loaded.keys), ["a", "b", "c"])
        XCTAssertEqual(loaded["a"]?.sharpness, 400)
        XCTAssertEqual(loaded["b"]?.textLines, ["TOTAL 8.37"])
        XCTAssertEqual(loaded["b"]?.textCoverage, 0.2)
    }

    func testSavedPrintsStayCloseEnoughToCompare() throws {
        let store = PhotoSignalsStore(fileURL: url)
        let original = signals(1)
        store.append(["a": original])
        let loaded = try XCTUnwrap(store.load()["a"])

        XCTAssertEqual(loaded.featurePrint.count, original.featurePrint.count)
        // Far inside the junk finder's tightest line, so a saved photo still matches its copy.
        let distance = try XCTUnwrap(JunkFinder.distance(original.featurePrint, loaded.featurePrint, under: 1))
        XCTAssertLessThan(distance, JunkRules.standard.sameDistance / 20)
    }

    func testRewriteDropsWhatIsGone() {
        let store = PhotoSignalsStore(fileURL: url)
        store.append(["a": signals(1), "b": signals(2)])
        store.rewrite(["b": signals(2)])
        XCTAssertEqual(Set(store.load().keys), ["b"])

        store.rewrite([:])
        XCTAssertTrue(store.load().isEmpty)
    }

    func testADamagedTailKeepsWhatCameBefore() throws {
        let store = PhotoSignalsStore(fileURL: url)
        store.append(["a": signals(1)])
        let handle = try FileHandle(forWritingTo: url)
        _ = try handle.seekToEnd()
        try handle.write(contentsOf: Data([0, 0, 9, 9, 1, 2, 3]))
        try handle.close()

        XCTAssertEqual(Set(store.load().keys), ["a"])
    }

    func testDuplicateFinderHandlesALibrarySizedInput() {
        // 3,000 unrelated photos and one planted copy: found, and quickly.
        var items: [MediaItem] = []
        var all: [MediaItem.ID: PhotoSignals] = [:]
        for index in 0..<3_000 {
            let id = "p\(index)"
            // Days apart, so only a true copy can match.
            items.append(makeItem(id: id, daysAgo: Double(index + 1)))
            var print = [Float](repeating: 0, count: 64)
            print[index % 64] = 0.8
            print[(index / 64) % 64] += 0.6
            let length = print.reduce(0) { $0 + $1 * $1 }.squareRoot()
            all[id] = PhotoSignals(featurePrint: print.map { $0 / length }, sharpness: 400 + Double(index), brightness: 0.5, darkFraction: 0)
        }
        items.append(makeItem(id: "copy"))
        all["copy"] = all["p1234"]

        let report = JunkFinder.find(in: items, signals: all, now: referenceDate)
        XCTAssertTrue(report.duplicates.contains { Set($0.items.map(\.id)) == ["p1234", "copy"] })
    }
}
