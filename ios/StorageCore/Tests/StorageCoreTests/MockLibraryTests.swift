import XCTest
@testable import StorageCore

final class MockMediaFactoryTests: XCTestCase {
    func testScenariosAreDeterministic() {
        for scenario in DemoScenario.allCases {
            XCTAssertEqual(MockMediaFactory.makeLibrary(for: scenario), MockMediaFactory.makeLibrary(for: scenario), "\(scenario)")
        }
    }

    func testTypicalScenarioShape() {
        let items = MockMediaFactory.makeLibrary(for: .typical)
        let summary = LibrarySummary(items: items)
        XCTAssertTrue((2_000...4_000).contains(summary[.photo].count))
        XCTAssertTrue((200...999).contains(summary[.video].count))
        XCTAssertTrue((200...999).contains(summary[.screenshot].count))
        XCTAssertGreaterThan(summary.largeVideos.count, 0)
        XCTAssertGreaterThan(summary.potentialSavings, 0)
        XCTAssertLessThan(summary.potentialSavings, summary.total.bytes)
    }

    func testLargeScenarioSize() {
        let items = MockMediaFactory.makeLibrary(for: .large)
        XCTAssertTrue((15_000...25_000).contains(items.count))
    }

    func testEmptyScenarioIsEmpty() {
        XCTAssertTrue(MockMediaFactory.makeLibrary(for: .empty).isEmpty)
    }

    func testIDsAreUnique() {
        let items = MockMediaFactory.makeLibrary(for: .large)
        XCTAssertEqual(Set(items.map(\.id)).count, items.count)
    }

    func testItemsAreInternallyConsistent() {
        for item in MockMediaFactory.makeLibrary(for: .typical) {
            XCTAssertGreaterThan(item.originalBytes, 0)
            XCTAssertEqual(item.currentBytes, item.originalBytes)
            XCTAssertNil(item.compressionLevel)
            XCTAssertEqual(item.duration != nil, item.category == .video, item.id)
            XCTAssertLessThanOrEqual(item.creationDate, MockMediaFactory.referenceDate)
            XCTAssertGreaterThan(item.pixelWidth, 0)
        }
    }

    func testSeededGeneratorRepeats() {
        var a = SeededGenerator(seed: 42)
        var b = SeededGenerator(seed: 42)
        XCTAssertEqual((0..<10).map { _ in a.next() }, (0..<10).map { _ in b.next() })
    }
}

final class MockServiceTests: XCTestCase {
    func testLoadMatchesFactory() async throws {
        let service = MockMediaLibraryService(scenario: .typical)
        let items = try await service.loadItems()
        XCTAssertEqual(items, MockMediaFactory.makeLibrary(for: .typical))
        XCTAssertTrue(service.isSimulated)
    }

    func testDeleteThenUndoThroughService() async throws {
        let service = MockMediaLibraryService(scenario: .typical)
        let original = try await service.loadItems()
        let target = Set(original.prefix(5).map(\.id))

        let result = try await service.deleteItems(withIDs: target)
        XCTAssertEqual(result.itemCount, 5)
        let afterDelete = try await service.loadItems()
        XCTAssertEqual(afterDelete.count, original.count - 5)
        let canUndo = await service.canUndo()
        XCTAssertTrue(canUndo)

        _ = try await service.undoLastChange()
        let restored = try await service.loadItems()
        XCTAssertEqual(restored, original)
    }

    func testResetRestoresScenarioAndClearsHistory() async throws {
        let service = MockMediaLibraryService(scenario: .typical)
        let original = try await service.loadItems()
        let videos = Set(original.filter { $0.category == .video }.prefix(20).map(\.id))
        _ = try await service.compressItems(withIDs: videos, level: .maximum)
        _ = try await service.deleteItems(withIDs: Set(original.prefix(3).map(\.id)))

        await service.reset(to: .typical)
        let afterReset = try await service.loadItems()
        XCTAssertEqual(afterReset, original)
        let canUndo = await service.canUndo()
        XCTAssertFalse(canUndo)
        let savings = await service.sessionSavings()
        XCTAssertEqual(savings, SessionSavings())
    }

    func testSwitchingScenarios() async throws {
        let service = MockMediaLibraryService(scenario: .typical)
        await service.reset(to: .empty)
        let scenario = await service.currentScenario()
        XCTAssertEqual(scenario, .empty)
        let items = try await service.loadItems()
        XCTAssertTrue(items.isEmpty)
        do {
            _ = try await service.deleteItems(withIDs: ["typical-0"])
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? MediaLibraryError, .noItemsSelected)
        }
    }
}
