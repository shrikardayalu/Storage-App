import Foundation
import Observation
import StorageCore

enum AppTab: Hashable {
    case home
    case library
    case settings
}

enum LibraryLayout: String, CaseIterable, Identifiable {
    case grid
    case list

    var id: String { rawValue }
    var title: String { self == .grid ? "Grid" : "List" }
    var systemImage: String { self == .grid ? "square.grid.3x3" : "list.bullet" }
}

/// Shared app state: the current library snapshot, navigation, filters, and
/// selection. Views read from it and call its methods; all data changes go
/// through the injected `MediaLibraryService`, so swapping the mock for a
/// PhotoKit-backed service later doesn't touch the views.
@MainActor
@Observable
final class AppModel {
    // MARK: Library snapshot

    private(set) var items: [MediaItem] = []
    private(set) var summary = LibrarySummary.empty
    private(set) var savings = SessionSavings()
    private(set) var canUndo = false
    private(set) var scenario: DemoScenario = .typical
    private(set) var hasLoaded = false
    /// True while a simulated operation is running.
    private(set) var isWorking = false
    var errorMessage: String?

    // MARK: Navigation and library UI state

    var selectedTab: AppTab = .home
    var libraryFilter: MediaFilter = .all
    var librarySort: MediaSort = .largestFirst
    var libraryLayout: LibraryLayout = .grid
    var isSelecting = false
    var isReviewPresented = false
    private(set) var selection = MediaSelection()

    // MARK: Dependencies

    let isSimulated: Bool
    private let service: any MediaLibraryService
    private let demo: (any DemoLibraryControlling)?
    @ObservationIgnored private var itemsByID: [MediaItem.ID: MediaItem] = [:]
    /// Bumped whenever `items` changes, so cached query results know to refresh.
    private var revision = 0
    @ObservationIgnored private var visibleCache: (key: VisibleKey, items: [MediaItem])?

    private struct VisibleKey: Equatable {
        let filter: MediaFilter
        let sort: MediaSort
        let revision: Int
    }

    init(service: any MediaLibraryService, demo: (any DemoLibraryControlling)?) {
        self.service = service
        self.demo = demo
        self.isSimulated = service.isSimulated
    }

    /// The app's only Phase 1 configuration: an in-memory demo library.
    static func demo(scenario: DemoScenario = .typical) -> AppModel {
        let service = MockMediaLibraryService(scenario: scenario, latency: .milliseconds(450))
        return AppModel(service: service, demo: service)
    }

    // MARK: Derived data

    /// Items for the Library tab after filtering and sorting. Cached, because
    /// sorting the 20,000-item scenario on every view update would be wasteful.
    var visibleItems: [MediaItem] {
        let key = VisibleKey(filter: libraryFilter, sort: librarySort, revision: revision)
        if let cache = visibleCache, cache.key == key {
            return cache.items
        }
        let result = MediaQuery.apply(filter: libraryFilter, sort: librarySort, to: items)
        visibleCache = (key, result)
        return result
    }

    var visibleBytes: Int64 {
        visibleItems.reduce(0) { $0 + $1.currentBytes }
    }

    var selectedItems: [MediaItem] {
        items.filter { selection.contains($0.id) }
    }

    var selectedBytes: Int64 {
        _ = revision // sizes change when items are compressed
        return selection.ids.reduce(0) { $0 + (itemsByID[$1]?.currentBytes ?? 0) }
    }

    /// Screenshots plus large videos: the default set for "Review suggestions".
    var suggestedIDs: Set<MediaItem.ID> {
        Set(items.lazy.filter { MediaFilter.screenshots.includes($0) || MediaFilter.largeVideos.includes($0) }.map(\.id))
    }

    var areAllVisibleSelected: Bool {
        selection.containsAll(visibleItems)
    }

    func item(withID id: MediaItem.ID) -> MediaItem? {
        itemsByID[id]
    }

    // MARK: Loading

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        if let demo {
            scenario = await demo.currentScenario()
        }
        await refresh()
    }

    private func refresh() async {
        do {
            apply(items: try await service.loadItems())
            savings = await service.sessionSavings()
            canUndo = await service.canUndo()
            hasLoaded = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func apply(items newItems: [MediaItem]) {
        items = newItems
        itemsByID = Dictionary(uniqueKeysWithValues: newItems.map { ($0.id, $0) })
        summary = LibrarySummary(items: newItems)
        selection.prune(keeping: Set(itemsByID.keys))
        revision += 1
    }

    // MARK: Navigation

    func showLibrary(filter: MediaFilter, sort: MediaSort = .largestFirst) {
        libraryFilter = filter
        librarySort = sort
        selectedTab = .library
    }

    /// Opens cleanup review. With nothing selected, pre-selects the suggestions.
    func reviewCleanup() {
        if selection.isEmpty {
            selection.select(suggestedIDs)
        }
        isReviewPresented = true
    }

    // MARK: Selection

    func isSelected(_ item: MediaItem) -> Bool {
        selection.contains(item.id)
    }

    func toggleSelection(_ item: MediaItem) {
        selection.toggle(item.id)
    }

    func selectAllVisible() {
        selection.select(visibleItems.map(\.id))
    }

    func deselectAllVisible() {
        selection.deselect(visibleItems.map(\.id))
    }

    func clearSelection() {
        selection.clear()
    }

    func endSelecting() {
        isSelecting = false
    }

    // MARK: Simulated cleanup

    func compressionPlan(level: CompressionLevel) -> CompressionPlan {
        CompressionPlan(items: selectedItems, level: level)
    }

    /// Simulates deleting the selected items. Returns the result, or nil on failure.
    func deleteSelected() async -> CleanupResult? {
        await perform { [service = self.service, ids = self.selection.ids] in
            try await service.deleteItems(withIDs: ids)
        }
    }

    /// Simulates compressing the selected items at `level`.
    func compressSelected(level: CompressionLevel) async -> CleanupResult? {
        await perform { [service = self.service, ids = self.selection.ids] in
            try await service.compressItems(withIDs: ids, level: level)
        }
    }

    func undoLastChange() async {
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await service.undoLastChange()
        } catch {
            errorMessage = error.localizedDescription
        }
        await refresh()
    }

    private func perform(_ operation: @escaping @Sendable () async throws -> CleanupResult) async -> CleanupResult? {
        guard !selection.isEmpty else {
            errorMessage = MediaLibraryError.noItemsSelected.localizedDescription
            return nil
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let result = try await operation()
            selection.clear()
            isSelecting = false
            await refresh()
            return result
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    // MARK: Demo controls

    var canResetDemo: Bool { demo != nil }

    /// Regenerates the demo library, discarding simulated changes and selection.
    func resetDemo(to newScenario: DemoScenario? = nil) async {
        guard let demo else { return }
        isWorking = true
        defer { isWorking = false }
        let target = newScenario ?? scenario
        await demo.reset(to: target)
        scenario = target
        selection.clear()
        isSelecting = false
        libraryFilter = .all
        await refresh()
    }
}

// MARK: - Previews

extension AppModel {
    /// A model already populated with a scenario, for SwiftUI previews.
    static func preview(_ scenario: DemoScenario = .typical) -> AppModel {
        let service = MockMediaLibraryService(scenario: scenario)
        let model = AppModel(service: service, demo: service)
        model.scenario = scenario
        model.apply(items: MockMediaFactory.makeLibrary(for: scenario))
        model.hasLoaded = true
        return model
    }
}
