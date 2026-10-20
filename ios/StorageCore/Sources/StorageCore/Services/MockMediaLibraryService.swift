import Foundation

/// A fully in-memory media library for Demo Mode.
///
/// It never touches Photos, the file system, or the network: every item comes
/// from `MockMediaFactory`, and delete/compress only change values held here.
public actor MockMediaLibraryService: MediaLibraryService, DemoLibraryControlling {
    public nonisolated let isSimulated = true

    private var scenario: DemoScenario
    private var library: MediaLibrary
    /// Optional pause before each operation so progress UI is visible. Zero in tests.
    private let latency: Duration

    public init(scenario: DemoScenario = .typical, latency: Duration = .zero) {
        self.scenario = scenario
        self.library = MediaLibrary(items: MockMediaFactory.makeLibrary(for: scenario))
        self.latency = latency
    }

    public func loadItems() async throws -> [MediaItem] {
        await pause()
        return library.items
    }

    public func deleteItems(withIDs ids: Set<MediaItem.ID>) async throws -> CleanupResult {
        await pause()
        return try library.delete(ids: ids)
    }

    public func compressItems(withIDs ids: Set<MediaItem.ID>, level: CompressionLevel) async throws -> CleanupResult {
        await pause()
        return try library.compress(ids: ids, level: level)
    }

    public func canUndo() async -> Bool {
        library.canUndo
    }

    public func undoLastChange() async throws -> CleanupResult {
        try library.undo()
    }

    public func sessionSavings() async -> SessionSavings {
        library.savings
    }

    public func currentScenario() async -> DemoScenario {
        scenario
    }

    public func reset(to scenario: DemoScenario) async {
        self.scenario = scenario
        library = MediaLibrary(items: MockMediaFactory.makeLibrary(for: scenario))
    }

    private func pause() async {
        guard latency > .zero else { return }
        try? await Task.sleep(for: latency)
    }
}
