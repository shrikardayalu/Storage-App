import StorageCore
import XCTest
@testable import StorageApp

/// Tests for the app's shared state, run against the mock service with no latency.
/// Pure business logic is covered in StorageCore's own tests.
@MainActor
final class AppModelTests: XCTestCase {
    private func makeModel(_ scenario: DemoScenario = .typical) async -> AppModel {
        let service = MockMediaLibraryService(scenario: scenario)
        let model = AppModel(service: service, demo: service)
        await model.loadIfNeeded()
        return model
    }

    func testLoadPopulatesSummaryFromItems() async {
        let model = await makeModel()
        XCTAssertTrue(model.hasLoaded)
        XCTAssertEqual(model.summary, LibrarySummary(items: model.items))
        XCTAssertGreaterThan(model.summary.total.count, 0)
    }

    func testVisibleItemsFollowFilterAndSort() async {
        let model = await makeModel()
        model.libraryFilter = .videos
        model.librarySort = .smallestFirst
        let visible = model.visibleItems
        XCTAssertTrue(visible.allSatisfy { $0.category == .video })
        XCTAssertEqual(visible.map(\.currentBytes), visible.map(\.currentBytes).sorted())
    }

    func testSelectAllVisibleAndTotals() async {
        let model = await makeModel()
        model.libraryFilter = .screenshots
        model.selectAllVisible()
        XCTAssertEqual(model.selection.count, model.summary[.screenshot].count)
        XCTAssertEqual(model.selectedBytes, model.summary[.screenshot].bytes)
        XCTAssertTrue(model.areAllVisibleSelected)
        model.deselectAllVisible()
        XCTAssertTrue(model.selection.isEmpty)
    }

    func testDeleteUpdatesDashboardAndUndoRestores() async {
        let model = await makeModel()
        let before = model.summary
        let video = model.items.filter { $0.category == .video }.max { $0.currentBytes < $1.currentBytes }!
        model.toggleSelection(video)

        let result = await model.deleteSelected()
        XCTAssertEqual(result?.bytesRecovered, video.currentBytes)
        XCTAssertNil(model.item(withID: video.id))
        XCTAssertEqual(model.summary.total.bytes, before.total.bytes - video.currentBytes)
        XCTAssertEqual(model.summary[.video].count, before[.video].count - 1)
        XCTAssertTrue(model.selection.isEmpty)
        XCTAssertTrue(model.canUndo)

        await model.undoLastChange()
        XCTAssertEqual(model.summary, before)
        XCTAssertNotNil(model.item(withID: video.id))
    }

    func testCompressUpdatesSizes() async {
        let model = await makeModel()
        let photo = model.items.first { $0.category == .photo && $0.isCompressionEligible }!
        model.toggleSelection(photo)
        let result = await model.compressSelected(level: .balanced)
        XCTAssertEqual(result?.itemCount, 1)
        XCTAssertLessThan(model.item(withID: photo.id)!.currentBytes, photo.currentBytes)
        XCTAssertEqual(model.savings.compressedCount, 1)
    }

    func testCompressingOnlyUnsupportedItemsReportsError() async {
        let model = await makeModel()
        let raw = model.items.first { $0.format == .proRAW }!
        model.toggleSelection(raw)
        let result = await model.compressSelected(level: .maximum)
        XCTAssertNil(result)
        XCTAssertNotNil(model.errorMessage)
    }

    func testReviewCleanupSelectsSuggestionsWhenEmpty() async {
        let model = await makeModel()
        model.reviewCleanup()
        XCTAssertTrue(model.isReviewPresented)
        XCTAssertEqual(model.selection.ids, model.suggestedIDs)
    }

    func testShowLibraryNavigatesWithFilter() async {
        let model = await makeModel()
        model.showLibrary(filter: .largeVideos)
        XCTAssertEqual(model.selectedTab, .library)
        XCTAssertEqual(model.libraryFilter, .largeVideos)
    }

    func testResetRestoresScenarioAndClearsState() async {
        let model = await makeModel()
        let original = model.items
        model.selectAllVisible()
        _ = await model.deleteSelected()
        XCTAssertTrue(model.items.isEmpty)

        await model.resetDemo()
        XCTAssertEqual(model.items, original)
        XCTAssertFalse(model.canUndo)
        XCTAssertTrue(model.savings.isEmpty)
    }

    func testSwitchingToEmptyScenario() async {
        let model = await makeModel()
        await model.resetDemo(to: .empty)
        XCTAssertEqual(model.scenario, .empty)
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertEqual(model.summary.potentialSavings, 0)
        model.reviewCleanup()
        XCTAssertTrue(model.selection.isEmpty)
    }
}
