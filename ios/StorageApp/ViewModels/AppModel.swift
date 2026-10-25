import Foundation
import Observation
import StorageCore

enum AppTab: Hashable {
    case home
    case library
    case settings
}

/// What the Recently Deleted guide is following up on.
struct CleanupGuide: Identifiable, Equatable {
    enum Kind: Equatable {
        case deleted(DeletionReceipt)
        case convertedLivePhotos([StillConversion])
    }

    let id = UUID()
    let kind: Kind
    /// IDs of what went to Recently Deleted, for the "look for these" thumbnails.
    let removedIDs: [MediaItem.ID]
    /// Space that should come back once Recently Deleted is emptied.
    let expectedBytes: Int64

    var count: Int { removedIDs.count }
}

/// Shared app state: real device storage readings, the Test Mode album scan,
/// selection, changes, and navigation. Views read from it and call its methods;
/// all device access goes through the injected services, so tests and previews
/// swap in mocks. The only changes go through `TestAlbumChangeService`, which
/// can reach nothing outside the test album.
@MainActor
@Observable
final class AppModel {
    // MARK: Device storage

    /// The most recent reading of the phone's storage.
    private(set) var deviceStorage: StorageSnapshot?
    /// Saved readings, oldest first. At most one per minute.
    private(set) var storageHistory = StorageHistory()
    private(set) var storageReadFailed = false

    // MARK: Test album scan

    /// The latest read-only scan of the test album, if one has run.
    private(set) var albumScan: LibraryScan?
    private(set) var photoAccess: PhotoAccess = .notDetermined
    private(set) var isScanning = false
    /// Why the last scan didn't finish, shown on the scan card.
    private(set) var scanError: PhotoScanError?
    var errorMessage: String?

    // MARK: Cleanup

    /// Items picked in the Library. Only IDs from the latest scan can be in it.
    private(set) var selection = MediaSelection()
    var isSelecting = false
    /// True while a delete or conversion is running.
    private(set) var isChanging = false
    /// The review sheet is open.
    var isReviewing = false
    /// Shown full screen after a cleanup, until the person closes it.
    var guide: CleanupGuide?
    /// The latest cleanup's guide, so it can be opened again from Home.
    private(set) var lastGuide: CleanupGuide?
    /// Waits for the review sheet to close before the guide opens.
    private var pendingGuide: CleanupGuide?
    /// Free space before the last cleanup, and since.
    private(set) var reclaim: ReclaimMeasurement?

    // MARK: Navigation

    var selectedTab: AppTab = .home
    /// Library tab filter; nil shows everything.
    var libraryGroup: ScanGroup?

    // MARK: Dependencies

    private let storageService: any DeviceStorageService
    private let historyStore: StorageHistoryStore
    private let photoScanner: any PhotoScanService
    private let photoChanges: any TestAlbumChangeService

    init(
        storage: any DeviceStorageService = MockDeviceStorageService(),
        historyStore: StorageHistoryStore = .inMemory,
        photoScanner: any PhotoScanService = MockPhotoScanService(items: []),
        photoChanges: any TestAlbumChangeService = MockPhotoLibrary(items: [])
    ) {
        self.storageService = storage
        self.historyStore = historyStore
        self.photoScanner = photoScanner
        self.photoChanges = photoChanges
        self.storageHistory = historyStore.load()
        self.deviceStorage = storageHistory.latest
    }

    /// One mock library that both scans and changes, for tests and previews.
    convenience init(storage: any DeviceStorageService = MockDeviceStorageService(), library: MockPhotoLibrary) {
        self.init(storage: storage, photoScanner: library, photoChanges: library)
    }

    /// The real configuration: volume readings saved in Application Support,
    /// a PhotoKit scanner, and PhotoKit changes, both limited to the Test Mode album.
    static func live() -> AppModel {
        AppModel(
            storage: VolumeStorageService(),
            historyStore: .applicationSupport,
            photoScanner: PhotoKitScanService(),
            photoChanges: PhotoKitTestAlbumChanges()
        )
    }

    // MARK: Device storage

    /// Reads the phone's storage and saves the reading. Called on launch and
    /// whenever the app comes back to the foreground. The card always shows the
    /// fresh reading; history skips it if the last one is under a minute old.
    func refreshDeviceStorage() async {
        do {
            let snapshot = try await storageService.currentSnapshot()
            deviceStorage = snapshot
            storageReadFailed = false
            reclaim?.record(snapshot)
            if storageHistory.append(snapshot) {
                try? historyStore.save(storageHistory)
            }
        } catch {
            storageReadFailed = deviceStorage == nil
        }
    }

    // MARK: Test album scan

    /// Reads the current Photos permission without prompting.
    func refreshPhotoAccess() async {
        photoAccess = await photoScanner.access()
    }

    /// Scans again on launch if Photos access was already given, so the
    /// Library is filled without a tap. Never shows the permission prompt.
    func scanIfAllowed() async {
        await refreshPhotoAccess()
        if photoAccess.canRead, albumScan == nil {
            await scanTestAlbum()
        }
    }

    /// Scans only the Test Mode album, asking for Photos access first if needed.
    /// Read-only: nothing in Photos changes.
    func scanTestAlbum() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }
        photoAccess = await photoScanner.access()
        if photoAccess == .notDetermined {
            photoAccess = await photoScanner.requestAccess()
        }
        do {
            let scan = LibraryScan(items: try await photoScanner.scanAlbum(named: TestMode.albumName))
            albumScan = scan
            selection.prune(keeping: Set(scan.items.map(\.id)))
            scanError = nil
        } catch let error as PhotoScanError {
            scanError = error
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Selection

    func toggleSelection(_ id: MediaItem.ID) {
        // Only items the latest scan found in the test album can be picked.
        guard albumScan?.items.contains(where: { $0.id == id }) == true else { return }
        selection.toggle(id)
    }

    func clearSelection() {
        selection.clear()
    }

    /// The picked items, biggest first.
    var selectedItems: [MediaItem] {
        albumScan?.items.filter { selection.contains($0.id) } ?? []
    }

    var convertibleLivePhotos: [MediaItem] {
        albumScan?.items.filter(\.isConvertibleLivePhoto) ?? []
    }

    // MARK: Changes (test album only)

    /// Checks the approved items against the album without changing anything.
    func safetyCheck(_ approved: Set<MediaItem.ID>) async -> Result<SafetyCheck, PhotoChangeError> {
        do {
            return .success(try await photoChanges.check(approved))
        } catch let error as PhotoChangeError {
            return .failure(error)
        } catch {
            return .failure(.verificationFailed(error.localizedDescription))
        }
    }

    /// Deletes exactly the items the person approved on the review screen, then
    /// opens the Recently Deleted guide. Returns nil on success, or why nothing changed.
    @discardableResult
    func delete(approved: Set<MediaItem.ID>) async -> PhotoChangeError? {
        await change(approved) { changes in
            let receipt = try await changes.delete(approved)
            return CleanupGuide(kind: .deleted(receipt), removedIDs: Array(receipt.deleted), expectedBytes: receipt.deletedBytes)
        }
    }

    /// Turns the approved Live Photos into stills, then opens the guide, since
    /// the originals wait in Recently Deleted. Returns nil on success, or why nothing changed.
    @discardableResult
    func convertToStills(approved: Set<MediaItem.ID>) async -> PhotoChangeError? {
        await change(approved) { changes in
            let results = try await changes.convertLivePhotosToStills(approved)
            let saved = results.reduce(Int64(0)) { $0 + $1.savedBytes }
            return CleanupGuide(kind: .convertedLivePhotos(results), removedIDs: results.map(\.originalID), expectedBytes: saved)
        }
    }

    private func change(
        _ approved: Set<MediaItem.ID>,
        _ work: (any TestAlbumChangeService) async throws -> CleanupGuide
    ) async -> PhotoChangeError? {
        guard !approved.isEmpty else { return .unsafe(SafetyCheck(approved: [], outsideTestAlbum: [], inOtherAlbums: [])) }
        guard !isChanging else { return .cancelled }
        isChanging = true
        defer { isChanging = false }

        // Free space before anything changes, to measure what comes back.
        await refreshDeviceStorage()
        let baseline = deviceStorage
        do {
            let guide = try await work(photoChanges)
            if let baseline {
                reclaim = ReclaimMeasurement(baseline: baseline, expectedBytes: guide.expectedBytes)
            }
            selection.deselect(approved)
            isSelecting = false
            lastGuide = guide
            if isReviewing {
                pendingGuide = guide
                isReviewing = false
            } else {
                self.guide = guide
            }
            // Re-read the album so the Library shows what's really there now.
            await scanTestAlbum()
            return nil
        } catch let error as PhotoChangeError {
            return error
        } catch {
            return .verificationFailed(error.localizedDescription)
        }
    }

    /// Reads free space again for the guide's "space back" figure.
    func measureReclaim() async {
        await refreshDeviceStorage()
    }

    /// Called once the review sheet has finished closing.
    func presentPendingGuide() {
        guard let pendingGuide else { return }
        self.pendingGuide = nil
        guide = pendingGuide
    }

    /// Opens the latest guide again, for when space is still waiting in Recently Deleted.
    func reopenGuide() {
        guide = lastGuide
    }

    /// Space still waiting in Recently Deleted from the latest cleanup, if any.
    var spaceWaiting: Int64? {
        guard let reclaim, !reclaim.isDone, reclaim.expectedBytes > 0 else { return nil }
        return reclaim.expectedBytes - reclaim.reclaimedBytes
    }

    func closeGuide() {
        guide = nil
    }

    // MARK: Navigation

    func showLibrary(group: ScanGroup?) {
        libraryGroup = group
        selectedTab = .library
    }
}

// MARK: - Previews

extension AppModel {
    /// A model already filled with sample readings and scan results, for SwiftUI previews.
    static func preview(items: [MediaItem] = []) -> AppModel {
        let model = AppModel()
        model.deviceStorage = StorageSnapshot(
            date: Date(),
            totalBytes: 127_400_000_000,
            availableBytes: 2_290_000_000,
            availableForImportantUsageBytes: 9_100_000_000
        )
        model.albumScan = LibraryScan(items: items)
        model.photoAccess = .granted
        return model
    }
}
