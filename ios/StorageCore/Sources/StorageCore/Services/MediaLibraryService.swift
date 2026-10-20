import Foundation

/// The boundary between the UI and wherever media actually lives.
///
/// Phase 1 ships only `MockMediaLibraryService`, which works on generated data
/// in memory. A later phase adds a PhotoKit-backed implementation of this same
/// protocol; the app's state layer talks only to this protocol, so the UI does
/// not change when the backing store does.
public protocol MediaLibraryService: Sendable {
    /// True for simulated services. The UI uses it to label results as simulated.
    var isSimulated: Bool { get }

    /// Every item currently in the library.
    func loadItems() async throws -> [MediaItem]

    /// Removes the given items.
    func deleteItems(withIDs ids: Set<MediaItem.ID>) async throws -> CleanupResult

    /// Compresses the given items where supported, skipping the rest.
    func compressItems(withIDs ids: Set<MediaItem.ID>, level: CompressionLevel) async throws -> CleanupResult

    /// Whether `undoLastChange()` can currently revert something.
    func canUndo() async -> Bool

    /// Reverts the most recent delete or compress, if the backing store allows it.
    func undoLastChange() async throws -> CleanupResult

    /// Storage recovered since the library was loaded or reset.
    func sessionSavings() async -> SessionSavings
}

/// Extra controls that only make sense for a simulated library.
public protocol DemoLibraryControlling: Sendable {
    func currentScenario() async -> DemoScenario
    /// Regenerates the library for `scenario`, discarding all simulated changes.
    func reset(to scenario: DemoScenario) async
}
