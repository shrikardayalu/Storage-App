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
        case keptBurstPicks(BurstReceipt)
        case shrunkVideo(VideoReplacement)
    }

    let id = UUID()
    let kind: Kind
    /// IDs of what went to Recently Deleted, for the "look for these" thumbnails.
    let removedIDs: [MediaItem.ID]
    /// Space that should come back once Recently Deleted is emptied.
    let expectedBytes: Int64

    var count: Int { removedIDs.count }

    /// What the results screen calls this cleanup.
    var resultTitle: String {
        switch kind {
        case .deleted: count == 1 ? "Deleted 1 item" : "Deleted \(count) items"
        case .convertedLivePhotos: count == 1 ? "1 Live Photo \u{2192} still" : "\(count) Live Photos \u{2192} stills"
        case .keptBurstPicks(let receipt): receipt.keepers.count == 1 ? "Best shot of 1 burst" : "Best shot of \(receipt.keepers.count) bursts"
        case .shrunkVideo(let result): result.wasTrimmed ? "Trimmed and shrank a video" : "Shrank a video"
        }
    }

    var resultSource: FreedSource {
        if case .shrunkVideo = kind { return .videos }
        return .photos
    }
}

/// One tap of the guide's Measure Again: when it finished, and how much more
/// free space came back during it.
struct ReclaimCheck: Equatable {
    let date: Date
    let gainedBytes: Int64
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
    /// True while the guide is re-reading free space.
    private(set) var isCheckingReclaim = false
    /// The guide's latest check, so it can say whether anything changed.
    private(set) var lastReclaimCheck: ReclaimCheck?

    // MARK: Duplicates + junk (Build Plan step 7)

    /// Measurements per photo, kept across scans so only new photos are measured again.
    private var photoSignals: [MediaItem.ID: PhotoSignals] = [:]
    /// What the junk finder suggests; nil until the photos have been measured once.
    private(set) var junkReport: JunkReport?
    private(set) var isAnalyzing = false
    /// Share of photos measured so far, 0 to 1.
    private(set) var analysisProgress: Double = 0

    // MARK: Files cleanup (Build Plan step 8)

    /// The one folder the person picked in Files. The app reads and deletes nothing outside it.
    private(set) var pickedFolder: URL?
    private(set) var folderScan: FolderScan?
    private(set) var fileReport: FileReport?
    private(set) var isScanningFolder = false
    private(set) var folderError: FileChangeError?
    /// The latest file deletion, with free space measured before and after.
    private(set) var lastFileDeletion: FileDeletionReceipt?
    private(set) var fileReclaim: ReclaimMeasurement?

    // MARK: Guides for other apps (Build Plan step 10)

    /// The other-app guide on screen, if any.
    var otherAppGuide: OtherAppGuide?
    /// The open guide's entry in `freed`, once its starting reading is taken.
    private(set) var guideEntry: FreedEntry.ID?
    /// True while a guide is re-reading free space.
    private(set) var isCheckingGuide = false

    // MARK: Results (Build Plan step 11)

    /// What every action gave back, measured against free space.
    private(set) var freed = FreedLedger()
    var isShowingResults = false
    /// Sample numbers for screenshots are never saved over the real results.
    private var showingSampleResults = false

    // MARK: Navigation

    var selectedTab: AppTab = .home
    /// Library tab filter; nil shows everything.
    var libraryGroup: ScanGroup?

    // MARK: Dependencies

    private let storageService: any DeviceStorageService
    private let historyStore: StorageHistoryStore
    private let freedStore: FreedLedgerStore
    private let photoScanner: any PhotoScanService
    private let photoChanges: any TestAlbumChangeService
    private let photoAnalyzer: any PhotoAnalysisService
    private let folderFiles: any FolderFilesService

    init(
        storage: any DeviceStorageService = MockDeviceStorageService(),
        historyStore: StorageHistoryStore = .inMemory,
        freedStore: FreedLedgerStore = .inMemory,
        photoScanner: any PhotoScanService = MockPhotoScanService(items: []),
        photoChanges: any TestAlbumChangeService = MockPhotoLibrary(items: []),
        photoAnalyzer: any PhotoAnalysisService = MockPhotoAnalysis(),
        folderFiles: any FolderFilesService = MockFolderFiles(files: [])
    ) {
        self.storageService = storage
        self.historyStore = historyStore
        self.freedStore = freedStore
        self.photoScanner = photoScanner
        self.photoChanges = photoChanges
        self.photoAnalyzer = photoAnalyzer
        self.folderFiles = folderFiles
        self.storageHistory = historyStore.load()
        self.deviceStorage = storageHistory.latest
        self.freed = freedStore.load()
    }

    /// One mock library that both scans and changes, for tests and previews.
    convenience init(
        storage: any DeviceStorageService = MockDeviceStorageService(),
        library: MockPhotoLibrary,
        analysis: MockPhotoAnalysis = MockPhotoAnalysis(),
        folder: MockFolderFiles = MockFolderFiles(files: [])
    ) {
        self.init(storage: storage, photoScanner: library, photoChanges: library, photoAnalyzer: analysis, folderFiles: folder)
    }

    /// The real configuration: volume readings saved in Application Support,
    /// a PhotoKit scanner, and PhotoKit changes, both limited to the Test Mode album.
    static func live() -> AppModel {
        // Smaller video copies from an earlier run that were never used.
        VideoExporter.removeLeftovers()
        return AppModel(
            storage: VolumeStorageService(),
            historyStore: .applicationSupport,
            freedStore: .applicationSupport,
            photoScanner: PhotoKitScanService(),
            photoChanges: PhotoKitTestAlbumChanges(),
            photoAnalyzer: PhotoKitAnalyzer(),
            folderFiles: PickedFolderFiles()
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
            freed.record(snapshot)
            saveFreed()
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
            if junkReport != nil { updateJunkReport() }
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

    /// Bursts in the test album that still have more than one shot.
    var bursts: [Burst] {
        Burst.all(in: albumScan?.items ?? [])
    }

    /// Videos in the test album that can be compressed or trimmed, biggest first.
    var shrinkableVideos: [MediaItem] {
        (albumScan?.items.filter(\.isShrinkableVideo) ?? []).sorted { ($0.currentBytes, $1.id) > ($1.currentBytes, $0.id) }
    }

    // MARK: Duplicates + junk

    /// Measures any photos not measured yet, then updates the junk report. Read-only.
    func findJunk() async {
        guard !isAnalyzing, let scan = albumScan else { return }
        isAnalyzing = true
        defer { isAnalyzing = false }
        let ids = Set(scan.items.map(\.id))
        photoSignals = photoSignals.filter { ids.contains($0.key) }
        let unmeasured = scan.items.filter { photoSignals[$0.id] == nil }
        analysisProgress = 0
        if !unmeasured.isEmpty {
            let found = await photoAnalyzer.analyze(unmeasured) { [weak self] value in
                Task { @MainActor in self?.analysisProgress = value }
            }
            photoSignals.merge(found) { _, new in new }
        }
        analysisProgress = 1
        updateJunkReport()
    }

    private func updateJunkReport() {
        junkReport = JunkFinder.find(in: albumScan?.items ?? [], signals: photoSignals, now: Date())
    }

    /// Removes the approved duplicates and junk, keeping the picked copy of each
    /// duplicate, then opens the Recently Deleted guide. Refuses if a removal
    /// would take every copy, or if a kept copy has left the album. Returns nil
    /// on success, or why nothing changed.
    @discardableResult
    func removeJunk(_ remove: Set<MediaItem.ID>, keeping keepers: Set<MediaItem.ID>) async -> PhotoChangeError? {
        guard let junkReport else { return .junkChanged("Nothing has been found yet.") }
        do {
            try junkReport.validate(remove: remove, keepers: keepers)
        } catch let error as PhotoChangeError {
            return error
        } catch {
            return .verificationFailed(error.localizedDescription)
        }
        // A kept copy that left the album means removing the others could lose the photo.
        if !keepers.isEmpty {
            switch await albumCheck(keepers) {
            case .success(let check) where !check.outsideTestAlbum.isEmpty:
                return .junkChanged("A copy you chose to keep is no longer in \u{201C}\(TestMode.albumName)\u{201D}.")
            case .failure(let error):
                return error
            case .success:
                break
            }
        }
        return await delete(approved: remove)
    }

    // MARK: Changes (test album only)

    /// Like `safetyCheck`, but a failed check comes back as its result, so a
    /// screen can mark the items it can't touch instead of only showing an error.
    func albumCheck(_ ids: Set<MediaItem.ID>) async -> Result<SafetyCheck, PhotoChangeError> {
        switch await safetyCheck(ids) {
        case .failure(.unsafe(let check)): .success(check)
        case let other: other
        }
    }

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

    /// Keeps the picked shot of each burst and moves the burst's other shots to
    /// Recently Deleted, then opens the guide. `keepers` maps burst ID to the
    /// picked shot. Returns nil on success, or why nothing changed.
    @discardableResult
    func keepBurstPicks(_ keepers: [String: MediaItem.ID]) async -> PhotoChangeError? {
        let keep = Set(keepers.values)
        let remove = Set(bursts.filter { keepers[$0.id] != nil }.flatMap(\.shots).map(\.id)).subtracting(keep)
        return await change(remove) { changes in
            let receipt = try await changes.keepBurstPicks(keep: keep, remove: remove)
            return CleanupGuide(kind: .keptBurstPicks(receipt), removedIDs: Array(receipt.removed), expectedBytes: receipt.removedBytes)
        }
    }

    /// Makes a smaller copy of one video and measures it. Nothing in Photos changes.
    func prepareVideo(_ id: MediaItem.ID, edit: VideoEdit) async -> Result<PreparedVideo, PhotoChangeError> {
        guard !isChanging else { return .failure(.cancelled) }
        isChanging = true
        defer { isChanging = false }
        do {
            return .success(try await photoChanges.prepareVideo(id, edit: edit))
        } catch let error as PhotoChangeError {
            return .failure(error)
        } catch {
            return .failure(.exportFailed(error.localizedDescription))
        }
    }

    /// Swaps the original video for its prepared copy, then opens the guide,
    /// since the original waits in Recently Deleted. Returns nil on success, or why nothing changed.
    @discardableResult
    func replaceVideo(with prepared: PreparedVideo) async -> PhotoChangeError? {
        await change([prepared.originalID]) { changes in
            let result = try await changes.replaceVideo(with: prepared)
            // The copy already takes its space, so emptying Recently Deleted gives back the whole original.
            return CleanupGuide(kind: .shrunkVideo(result), removedIDs: [result.originalID], expectedBytes: result.originalBytes)
        }
    }

    func discard(_ prepared: PreparedVideo) async {
        await photoChanges.discard(prepared)
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
                freed.open(guide.resultSource, title: guide.resultTitle, baseline: baseline, expectedBytes: guide.expectedBytes)
                saveFreed()
            }
            lastReclaimCheck = nil
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

    /// Reads free space a few times over several seconds for the guide's
    /// "space back" figure, because iOS can take a moment to count the space
    /// from an emptied Recently Deleted. Stops early once the space is back.
    /// Apps can't look inside Recently Deleted, so free space is the proof.
    func checkReclaim(readings: Int = 6, every interval: Duration = .seconds(2)) async {
        guard !isCheckingReclaim else { return }
        isCheckingReclaim = true
        defer { isCheckingReclaim = false }
        let before = reclaim?.reclaimedBytes ?? 0
        for index in 0..<max(1, readings) {
            if index > 0 { try? await Task.sleep(for: interval) }
            if Task.isCancelled { break }
            await refreshDeviceStorage()
            if reclaim?.isDone != false { break }
        }
        lastReclaimCheck = ReclaimCheck(date: Date(), gainedBytes: (reclaim?.reclaimedBytes ?? 0) - before)
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

    // MARK: Files cleanup

    /// Starts working with the folder the person just picked, and scans it. Read-only.
    func pick(folder: URL) async {
        pickedFolder = folder
        folderScan = nil
        fileReport = nil
        lastFileDeletion = nil
        fileReclaim = nil
        await scanFolder()
    }

    /// Reads the picked folder again. Read-only.
    func scanFolder() async {
        guard let pickedFolder, !isScanningFolder else { return }
        isScanningFolder = true
        defer { isScanningFolder = false }
        do {
            let scan = try await folderFiles.scan(pickedFolder)
            folderScan = scan
            fileReport = FileCleanup.report(for: scan, now: Date())
            folderError = nil
        } catch let error as FileChangeError {
            folderError = error
        } catch {
            folderError = .verificationFailed(error.localizedDescription)
        }
    }

    /// Deletes exactly the approved files from the picked folder for good, then
    /// scans it again and measures free space. Refuses if a deletion would take
    /// every copy of a duplicate. Returns nil on success, or why nothing was deleted.
    @discardableResult
    func deleteFiles(_ approved: [FileItem], keeping keepers: [FileItem]) async -> FileChangeError? {
        guard let pickedFolder, let fileReport, !approved.isEmpty else { return .changed("Nothing was approved.") }
        guard !isChanging else { return .changed("Something else is still running.") }
        do {
            try fileReport.validate(remove: Set(approved.map(\.id)), keepers: Set(keepers.map(\.id)))
        } catch let error as FileChangeError {
            return error
        } catch {
            return .verificationFailed(error.localizedDescription)
        }
        isChanging = true
        defer { isChanging = false }

        await refreshDeviceStorage()
        let baseline = deviceStorage
        do {
            let receipt = try await folderFiles.delete(approved, keeping: keepers, in: pickedFolder)
            lastFileDeletion = receipt
            if let baseline {
                fileReclaim = ReclaimMeasurement(baseline: baseline, expectedBytes: receipt.deletedBytes)
                let count = receipt.deleted.count
                freed.open(.files, title: count == 1 ? "Deleted 1 file" : "Deleted \(count) files", baseline: baseline, expectedBytes: receipt.deletedBytes)
                saveFreed()
            }
            // Files skip Recently Deleted, so the space should be back already.
            await refreshDeviceStorage()
            if let deviceStorage { fileReclaim?.record(deviceStorage) }
            await scanFolder()
            return nil
        } catch let error as FileChangeError {
            await scanFolder()
            return error
        } catch {
            return .verificationFailed(error.localizedDescription)
        }
    }

    // MARK: Guides for other apps

    func open(_ guide: OtherAppGuide) {
        closeOtherAppGuide()
        otherAppGuide = guide
    }

    /// Takes the guide's starting reading, so its free-space check measures
    /// only what changed while it was open.
    func startMeasuring(_ guide: OtherAppGuide) async {
        guard guideEntry == nil else { return }
        await refreshDeviceStorage()
        guard otherAppGuide == guide, guideEntry == nil, let baseline = deviceStorage else { return }
        guideEntry = freed.open(.guides, title: guide.title, baseline: baseline)
        saveFreed()
    }

    /// Free space the open guide has given back so far.
    var guideFreedBytes: Int64 {
        guideEntry.flatMap { freed[$0]?.measuredBytes } ?? 0
    }

    /// Reads free space a few times, since iOS can take a moment to count
    /// space another app just gave back.
    func checkGuide(readings: Int = 3, every interval: Duration = .seconds(2)) async {
        guard !isCheckingGuide else { return }
        isCheckingGuide = true
        defer { isCheckingGuide = false }
        for index in 0..<max(1, readings) {
            if index > 0 { try? await Task.sleep(for: interval) }
            if Task.isCancelled { break }
            await refreshDeviceStorage()
        }
    }

    /// Ends the guide's measurement. A guide that gave nothing back leaves no entry.
    func closeOtherAppGuide() {
        if let guideEntry {
            freed.close(guideEntry)
            saveFreed()
        }
        guideEntry = nil
        otherAppGuide = nil
    }

    // MARK: Results

    /// Clears the results to start counting again. Changes nothing on the phone.
    func resetResults() {
        freed = FreedLedger()
        guideEntry = nil
        saveFreed()
    }

    private func saveFreed() {
        guard !showingSampleResults else { return }
        try? freedStore.save(freed)
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

    /// Sample results for previews and screenshots. Kept in memory only.
    func showSampleResults() {
        let start = Date().addingTimeInterval(-3_600)
        var free: Int64 = 2_290_000_000
        func reading(_ minutes: Double) -> StorageSnapshot {
            StorageSnapshot(date: start.addingTimeInterval(minutes * 60), totalBytes: 127_400_000_000,
                            availableBytes: free, availableForImportantUsageBytes: free)
        }
        var ledger = FreedLedger()
        let actions: [(source: FreedSource, title: String, bytes: Int64)] = [
            (.photos, "Deleted 14 items", 1_840_000_000),
            (.videos, "Trimmed and shrank a video", 610_000_000),
            (.files, "Deleted 3 files", 420_000_000),
            (.guides, "WhatsApp", 2_130_000_000),
        ]
        for (index, action) in actions.enumerated() {
            let minutes = Double(index) * 10
            let id = ledger.open(action.source, title: action.title, baseline: reading(minutes),
                                 expectedBytes: action.source == .guides ? 0 : action.bytes)
            free += action.bytes
            ledger.record(reading(minutes + 5))
            ledger.close(id)
        }
        showingSampleResults = true
        freed = ledger
        deviceStorage = reading(50)
    }
}
