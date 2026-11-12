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
        /// "Shrink all at once": the videos swapped, and how many were left alone
        /// because their copy wouldn't have been smaller.
        case shrunkVideos([VideoReplacement], skipped: Int)
        /// One-tap Photo Cleanup: what was removed, and the Live Photos made into stills.
        case photoCleanup(DeletionReceipt?, [StillConversion])
        /// PNG screenshots replaced by smaller HEIC copies; the PNGs are in Recently Deleted.
        case resavedScreenshots(ScreenshotResaveReceipt)
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
        case .shrunkVideos: count == 1 ? "Shrank 1 video" : "Shrank \(count) videos"
        case .photoCleanup: count == 1 ? "Photo Cleanup: 1 photo" : "Photo Cleanup: \(count) photos"
        case .resavedScreenshots: count == 1 ? "Re-saved 1 screenshot" : "Re-saved \(count) screenshots"
        }
    }

    var resultSource: FreedSource {
        switch kind {
        case .shrunkVideo, .shrunkVideos: return .videos
        default: return .photos
        }
    }
}

/// One tap of the guide's Measure Again: when it finished, and how much more
/// free space came back during it.
struct ReclaimCheck: Equatable {
    let date: Date
    let gainedBytes: Int64
}

/// Shared app state: real device storage readings, the photo library scan,
/// selection, changes, and navigation. Views read from it and call its methods;
/// all device access goes through the injected services, so tests and previews
/// swap in mocks. The only changes go through `PhotoChangeService`, which
/// changes only the items the person approved on a review screen.
@MainActor
@Observable
final class AppModel {
    // MARK: Device storage

    /// The most recent reading of the phone's storage.
    private(set) var deviceStorage: StorageSnapshot?
    /// Saved readings, oldest first. At most one per minute.
    private(set) var storageHistory = StorageHistory()
    private(set) var storageReadFailed = false

    // MARK: Storage health + restart coach

    /// Why Home suggests a look at storage, if it does.
    var storageWarning: StorageWarning? {
        StorageWarning.evaluate(latest: deviceStorage, history: storageHistory)
    }

    /// Takes a fresh reading as the baseline, so the next open after a
    /// restart can show what came back.
    func startRestart() async {
        await refreshDeviceStorage()
        guard let baseline = deviceStorage else { return }
        restartCoach = RestartCoachState(pending: PendingRestart(baseline: baseline), result: nil)
        saveRestartCoach()
    }

    func cancelRestart() {
        restartCoach.pending = nil
        saveRestartCoach()
    }

    func dismissRestartResult() {
        restartCoach.result = nil
        saveRestartCoach()
    }

    /// On every reading: if the phone started up since the baseline, measure
    /// what came back and add it to the results. A suggestion nobody acted on
    /// is dropped after a few days.
    private func checkForRestart(_ snapshot: StorageSnapshot) {
        guard let pending = restartCoach.pending else { return }
        if pending.restarted(now: snapshot.date, uptime: uptime()) {
            let result = RestartResult(date: snapshot.date, gainedBytes: pending.gained(now: snapshot))
            if result.gaveSpaceBack {
                let id = freed.open(.restart, title: "Restarted your iPhone", baseline: pending.baseline)
                freed.record(snapshot)
                freed.close(id)
            }
            restartCoach = RestartCoachState(pending: nil, result: result)
            saveRestartCoach()
        } else if pending.isExpired(now: snapshot.date) {
            cancelRestart()
        }
    }

    private func saveRestartCoach() {
        try? restartStore.save(restartCoach)
    }

    // MARK: Library scan

    /// The latest read-only scan of the photo library, if one has run.
    private(set) var libraryScan: LibraryScan?
    /// What each tool works on, sorted and totalled once per scan. Screens read
    /// these many times per redraw, so they must never be worked out on the spot:
    /// with a whole library that froze the app.
    private var lists = LibraryLists()
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

    /// Measurements per photo, kept across scans and launches so only new photos are measured again.
    private var photoSignals: [MediaItem.ID: PhotoSignals] = [:]
    /// Whether the saved measurements have been read from disk yet.
    private var loadedSavedSignals = false
    /// The measuring that's running, if any. The model owns it, so it carries
    /// on when the screen that asked for it goes away.
    private var junkTask: Task<Void, Never>?
    /// True once every photo in the latest scan has been through the junk finder this session.
    private(set) var junkAnalysisFinished = false
    /// True once every Live Photo in this scan has been checked. The rest of the
    /// library can still be measuring; a Live Photo only depends on its own signals.
    private(set) var liveCheckFinished = false
    /// Share of Live Photos checked so far, 0 to 1. Separate from `analysisProgress`,
    /// which covers every photo the junk finder still has to look at.
    private(set) var liveAnalysisProgress: Double = 0
    /// Photos this run already tried to measure, including ones Photos couldn't hand over.
    private var measuredAttempts: Set<MediaItem.ID> = []
    /// Bumped each time a junk report starts, so a slow older pass can't overwrite a newer one.
    private var reportGeneration = 0
    /// The report being built in the background, if any. Measuring doesn't wait for it.
    private var reportTask: Task<Void, Never>?
    /// How many photos are measured between saves and progress steps.
    static let analysisBatch = 100
    /// What the junk finder suggests; nil until the photos have been measured once.
    private(set) var junkReport: JunkReport?
    /// One-tap Photo Cleanup for the scanned library, once the photos have been checked.
    private(set) var photoCleanupPlan: PhotoCleanupPlan?
    /// Why each Live Photo is better left Live (people, pets, scenery, a
    /// favorite, not checked yet). Nil until the photos have been checked once.
    private(set) var liveKeepReasons: [MediaItem.ID: KeepReason]?
    /// The Live Photos a still would do for. Nil until the photos have been checked once.
    private(set) var suggestedLivePhotos: [MediaItem]?
    /// Every junk suggestion as a swipe card, including ones already kept on a swipe.
    private var allSwipeCandidates: [SwipeCandidate]?
    /// The swipe feed: every junk suggestion except photos already kept on a swipe.
    private(set) var swipeCandidates: [SwipeCandidate]?
    private(set) var isAnalyzing = false
    /// Share of photos measured so far, 0 to 1.
    private(set) var analysisProgress: Double = 0
    /// Photos swiped right (kept) in Swipe to clean. They don't come back in
    /// the swipe feed, or count toward its saving, once a swipe session is done.
    private(set) var swipeKept: Set<MediaItem.ID> = []
    private let swipeKeptDefaults: UserDefaults?
    static let swipeKeptKey = "swipe.kept"

    /// Remembers photos kept in Swipe to clean so they aren't offered again.
    func markSwipeKept(_ ids: some Sequence<MediaItem.ID>) {
        let before = swipeKept.count
        swipeKept.formUnion(ids)
        guard swipeKept.count != before else { return }
        swipeKeptDefaults?.set(Array(swipeKept), forKey: Self.swipeKeptKey)
        swipeCandidates = allSwipeCandidates?.filter { !swipeKept.contains($0.id) }
    }

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

    // MARK: Storage health + restart coach (Build Plan step 9)

    /// A restart the person is about to do, and what the last one gave back.
    private(set) var restartCoach = RestartCoachState()
    /// The restart guide is on screen.
    var isShowingRestartGuide = false

    // MARK: Navigation

    var selectedTab: AppTab = .home
    /// Library tab filter; nil shows everything.
    var libraryGroup: ScanGroup?

    // MARK: Dependencies

    private let storageService: any DeviceStorageService
    private let historyStore: StorageHistoryStore
    private let freedStore: FreedLedgerStore
    private let photoScanner: any PhotoScanService
    private let photoChanges: any PhotoChangeService
    private let photoAnalyzer: any PhotoAnalysisService
    private let signalsStore: PhotoSignalsStore
    private let folderFiles: any FolderFilesService
    private let restartStore: RestartCoachStore
    /// Time since the phone started, including time asleep.
    private let uptime: @Sendable () -> TimeInterval

    init(
        storage: any DeviceStorageService = MockDeviceStorageService(),
        historyStore: StorageHistoryStore = .inMemory,
        freedStore: FreedLedgerStore = .inMemory,
        photoScanner: any PhotoScanService = MockPhotoScanService(items: []),
        photoChanges: any PhotoChangeService = MockPhotoLibrary(items: []),
        photoAnalyzer: any PhotoAnalysisService = MockPhotoAnalysis(),
        signalsStore: PhotoSignalsStore = .inMemory,
        folderFiles: any FolderFilesService = MockFolderFiles(files: []),
        restartStore: RestartCoachStore = .inMemory,
        swipeKeptDefaults: UserDefaults? = nil,
        uptime: @escaping @Sendable () -> TimeInterval = { 1_000_000_000 }
    ) {
        self.storageService = storage
        self.swipeKeptDefaults = swipeKeptDefaults
        self.swipeKept = Set(swipeKeptDefaults?.stringArray(forKey: Self.swipeKeptKey) ?? [])
        self.restartStore = restartStore
        self.uptime = uptime
        self.historyStore = historyStore
        self.freedStore = freedStore
        self.photoScanner = photoScanner
        self.photoChanges = photoChanges
        self.photoAnalyzer = photoAnalyzer
        self.signalsStore = signalsStore
        self.folderFiles = folderFiles
        self.storageHistory = historyStore.load()
        self.deviceStorage = storageHistory.latest
        self.freed = freedStore.load()
        self.restartCoach = restartStore.load()
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
    /// a PhotoKit scanner of the whole library, and PhotoKit changes that
    /// touch only what the person approves.
    static func live() -> AppModel {
        // Smaller video copies from an earlier run that were never used.
        VideoExporter.removeLeftovers()
        return AppModel(
            storage: VolumeStorageService(),
            historyStore: .applicationSupport,
            freedStore: .applicationSupport,
            photoScanner: PhotoKitScanService(),
            photoChanges: PhotoKitChanges(),
            photoAnalyzer: PhotoKitAnalyzer(),
            // A cache: iOS may clear it when space is short, and it's measured again.
            signalsStore: PhotoSignalsStore(fileURL: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
                .appendingPathComponent("photo-signals.bin")),
            folderFiles: PickedFolderFiles(),
            restartStore: .applicationSupport,
            swipeKeptDefaults: .standard,
            uptime: { SystemUptime.sinceStart() }
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
            checkForRestart(snapshot)
            saveFreed()
            if storageHistory.append(snapshot) {
                try? historyStore.save(storageHistory)
            }
        } catch {
            storageReadFailed = deviceStorage == nil
        }
    }

    // MARK: Library scan

    /// Reads the current Photos permission without prompting.
    func refreshPhotoAccess() async {
        photoAccess = await photoScanner.access()
    }

    /// Scans again on launch if Photos access was already given, so the
    /// Library is filled without a tap. Never shows the permission prompt.
    func scanIfAllowed() async {
        await refreshPhotoAccess()
        guard photoAccess.canRead, libraryScan == nil else { return }
        // Show what the last launch found straight away, then check it against
        // the library. Changes never rely on it: each one looks its items up fresh.
        if let items = await photoScanner.lastScan(), !items.isEmpty, libraryScan == nil, !isScanning {
            let (scan, lists) = await Task.detached(priority: .userInitiated) { Self.organize(items) }.value
            if libraryScan == nil {
                libraryScan = scan
                self.lists = lists
            }
        }
        await scanLibrary()
    }

    /// Sorts and totals a scan's items. Slow on a big library, so call it off the main thread.
    private nonisolated static func organize(_ items: [MediaItem]) -> (LibraryScan, LibraryLists) {
        let scan = LibraryScan(items: items)
        return (scan, LibraryLists(scan))
    }

    /// Scans the photo library, asking for Photos access first if needed. With
    /// limited access it sees only the photos the person picked.
    /// Read-only: nothing in Photos changes.
    func scanLibrary() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }
        photoAccess = await photoScanner.access()
        if photoAccess == .notDetermined {
            photoAccess = await photoScanner.requestAccess()
        }
        do {
            let items = try await photoScanner.scanLibrary()
            // Sorting and totalling a big library is kept off the main thread.
            let previous = libraryScan?.items
            let organized = await Task.detached(priority: .userInitiated) { () -> (LibraryScan, LibraryLists)? in
                let (scan, lists) = Self.organize(items)
                // Nothing changed since the last scan: keep it, so no screen has to start over.
                return scan.items == previous ? nil : (scan, lists)
            }.value
            scanError = nil
            guard let (scan, lists) = organized else { return }
            libraryScan = scan
            self.lists = lists
            selection.prune(keeping: lists.ids)
            // A new library needs measuring again. The report below uses whatever
            // is already known, so the savings figures don't wait for that.
            junkAnalysisFinished = false
            if junkReport != nil { await updateJunkReport() }
            if needsPhotoMeasurement() {
                // A run for the previous library has to finish before this one starts.
                if junkTask != nil { await junkTask?.value }
                startFindingJunk()
            } else if junkReport != nil {
                junkAnalysisFinished = true
                liveCheckFinished = true
                liveAnalysisProgress = 1
            }
        } catch let error as PhotoScanError {
            scanError = error
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Selection

    func toggleSelection(_ id: MediaItem.ID) {
        // Only items the latest scan found can be picked.
        guard lists.ids.contains(id) else { return }
        selection.toggle(id)
    }

    /// Picks or unpicks many items in one go.
    func setSelected(_ selected: Bool, _ ids: some Sequence<MediaItem.ID>) {
        if selected {
            selection.select(ids.filter(lists.ids.contains))
        } else {
            selection.deselect(ids)
        }
    }

    func clearSelection() {
        selection.clear()
    }

    /// The picked items, biggest first.
    var selectedItems: [MediaItem] {
        libraryScan?.items.filter { selection.contains($0.id) } ?? []
    }

    var convertibleLivePhotos: [MediaItem] { lists.convertibleLivePhotos }

    /// Screenshots still saved as PNG, biggest first.
    var resavableScreenshots: [MediaItem] { lists.resavableScreenshots }

    /// What re-saving every PNG screenshot could save, estimated.
    var screenshotSaving: Int64 { lists.screenshotSaving }

    /// Bursts that still have more than one shot.
    var bursts: [Burst] { lists.bursts }

    /// Videos that can be compressed or trimmed, biggest first.
    var shrinkableVideos: [MediaItem] { lists.shrinkableVideos }

    /// Videos the shrink tool leaves alone: slo-mo, Cinematic, ProRes and very small ones.
    var videosLeftAlone: Int { lists.videoCount - lists.shrinkableVideos.count }

    /// What Live Photos to stills could save: the suggested ones once the
    /// photos have been checked, every Live Photo before that.
    var livePhotoSaving: Int64 {
        // Until every Live Photo has been checked, this is the whole video portion.
        // The precise figure replaces it the moment that check finishes.
        guard liveCheckFinished, let suggested = suggestedLivePhotos else { return lists.livePhotoSaving }
        return suggested.reduce(Int64(0)) { $0 + $1.livePhotoVideoBytes }
    }

    /// What keeping the suggested shot of each burst could save.
    var burstSaving: Int64 { lists.burstSaving }

    /// What shrinking every video with the smaller option, untrimmed, could save.
    var videoSaving: Int64 { lists.videoSaving }

    // MARK: Duplicates + junk

    /// Measures any photos not measured yet, then updates the junk report, and
    /// returns when that's done. Read-only. If it's already running, this
    /// waits for the run in progress.
    func findJunk() async {
        startFindingJunk()
        await junkTask?.value
    }

    /// Starts `findJunk` without waiting for it. A whole library takes a
    /// while the first time; measurements are saved as they're made, so a run
    /// that's cut short picks up where it stopped.
    func startFindingJunk() {
        // Already done for this scan: opening a tool must not put the bar back
        // and run the whole pass again.
        guard junkTask == nil, libraryScan != nil, !junkAnalysisFinished else { return }
        isAnalyzing = true
        analysisProgress = 0
        measuredAttempts = []
        junkTask = Task { [weak self] in
            await self?.measurePhotos()
            self?.junkTask = nil
            self?.isAnalyzing = false
        }
    }

    /// Photos that still need a measurement. Videos and burst shots have their own tools.
    private func needsPhotoMeasurement() -> Bool {
        guard let items = libraryScan?.items else { return false }
        return items.contains {
            $0.category != .video && $0.burstID == nil && (photoSignals[$0.id]?.version ?? 0) < PhotoSignals.currentVersion
        }
    }

    private func measurePhotos() async {
        guard let scan = libraryScan else { return }
        let store = signalsStore
        if !loadedSavedSignals {
            loadedSavedSignals = true
            let saved = await Task.detached(priority: .userInitiated) { store.load() }.value
            photoSignals.merge(saved) { current, _ in current }
        }
        let ids = lists.ids
        let savedCount = photoSignals.count
        photoSignals = photoSignals.filter { ids.contains($0.key) }
        let dropped = savedCount - photoSignals.count

        // Videos and burst shots aren't measured; they have their own tools.
        // Measurements from an older version of the app are made again.
        // Live Photos go first: their screen can finish as soon as they have,
        // without waiting for every other photo in the library.
        let liveIDs = Set(lists.convertibleLivePhotos.map(\.id))
        let pending = scan.items.enumerated().filter { _, item in
            item.category != .video && item.burstID == nil && (photoSignals[item.id]?.version ?? 0) < PhotoSignals.currentVersion
        }.sorted { lhs, rhs in
            let leftLive = liveIDs.contains(lhs.element.id)
            let rightLive = liveIDs.contains(rhs.element.id)
            if leftLive != rightLive { return leftLive }
            return lhs.offset < rhs.offset
        }.map(\.element)
        let outdated = pending.contains { photoSignals[$0.id] != nil }

        // Numbers from what's already saved, before the first new photo is measured.
        await publishLiveProgress()
        scheduleJunkReport()

        var done = 0
        var lastReport = Date()
        while done < pending.count, !Task.isCancelled {
            let batch = Array(pending[done..<min(done + Self.analysisBatch, pending.count)])
            let base = done
            let total = pending.count
            let batchIDs = Set(batch.map(\.id))
            let liveTotal = lists.convertibleLivePhotos.count
            let liveBatch = batch.reduce(0) { $0 + (liveIDs.contains($1.id) ? 1 : 0) }
            let liveBase = lists.convertibleLivePhotos.reduce(0) { count, item in
                guard !batchIDs.contains(item.id) else { return count }
                let checked = item.traits.contains(.favorite)
                    || (photoSignals[item.id]?.version ?? 0) >= PhotoSignals.currentVersion
                    || measuredAttempts.contains(item.id)
                return count + (checked ? 1 : 0)
            }
            let found = await photoAnalyzer.analyze(batch) { [weak self] value in
                let analysis = total > 0 ? (Double(base) + value * Double(batch.count)) / Double(total) : 1
                let live = liveTotal > 0 && liveBatch > 0
                    ? min(1, (Double(liveBase) + value * Double(liveBatch)) / Double(liveTotal))
                    : nil
                Task { @MainActor in
                    guard let self, self.isAnalyzing else { return }
                    self.analysisProgress = max(self.analysisProgress, analysis)
                    if let live { self.liveAnalysisProgress = max(self.liveAnalysisProgress, live) }
                }
            }
            photoSignals.merge(found) { _, new in new }
            done += batch.count
            measuredAttempts.formUnion(batchIDs)
            analysisProgress = max(analysisProgress, total > 0 ? Double(done) / Double(total) : 1)
            if !found.isEmpty {
                await Task.detached(priority: .utility) { store.append(found) }.value
            }
            await publishLiveProgress()
            // A fresh report while measuring, without making the next photo wait for it.
            if reportTask == nil, done == pending.count || Date().timeIntervalSince(lastReport) > 2 {
                scheduleJunkReport()
                lastReport = Date()
            }
        }
        // Photos that are gone pile up in the saved file, and so do
        // measurements that were made again; tidy it now and then.
        if dropped > max(500, photoSignals.count / 5) || (outdated && !Task.isCancelled) {
            let current = photoSignals
            await Task.detached(priority: .utility) { store.rewrite(current) }.value
        }
        analysisProgress = 1
        await publishLiveProgress()
        await reportTask?.value
        reportTask = nil
        await updateJunkReport()
        junkAnalysisFinished = !Task.isCancelled && libraryScan?.date == scan.date
    }

    /// Starts a junk report if one isn't already running. Measuring keeps going either way.
    private func scheduleJunkReport() {
        guard reportTask == nil else { return }
        reportTask = Task { [weak self] in
            await self?.updateJunkReport()
            self?.reportTask = nil
        }
    }

    /// Works the report out off the main thread: comparing every photo with
    /// every other takes a moment on a big library.
    private func updateJunkReport() async {
        reportGeneration += 1
        let generation = reportGeneration
        let items = libraryScan?.items ?? []
        let signals = photoSignals
        let (report, candidates) = await Task.detached(priority: .userInitiated) {
            let report = JunkFinder.find(in: items, signals: signals, now: Date())
            return (report, SwipeCandidate.all(from: report))
        }.value
        // A newer pass started while this one was comparing photos. Drop this result.
        guard generation == reportGeneration, !Task.isCancelled else { return }
        junkReport = report
        allSwipeCandidates = candidates
        swipeCandidates = candidates.filter { !swipeKept.contains($0.id) }
        await publishLiveProgress()
    }

    /// Which Live Photos a still would do for, from measurements made so far.
    /// An older measurement doesn't count: it's being made again.
    private func publishLiveProgress() async {
        let livePhotos = lists.convertibleLivePhotos
        let signals = photoSignals
        let attempted = measuredAttempts
        let (keep, suggested, doneCount) = await Task.detached(priority: .userInitiated) {
            let current = signals.filter { $0.value.version >= PhotoSignals.currentVersion }
            let keep = LiveStills.keepReasons(for: livePhotos, signals: current)
            let suggested = livePhotos.filter { keep[$0.id] == nil }
            let done = livePhotos.reduce(into: 0) { count, item in
                if item.traits.contains(.favorite) || current[item.id] != nil || attempted.contains(item.id) {
                    count += 1
                }
            }
            return (keep, suggested, done)
        }.value
        guard !Task.isCancelled else { return }
        liveKeepReasons = keep
        suggestedLivePhotos = suggested
        if let junkReport {
            photoCleanupPlan = PhotoCleanupPlan(report: junkReport, livePhotos: suggested)
        }
        let total = livePhotos.count
        liveAnalysisProgress = total == 0 ? 1 : Double(doneCount) / Double(total)
        liveCheckFinished = total == 0 || doneCount == total
    }

    /// Removes the approved duplicates and junk, keeping the picked copy of each
    /// duplicate, then opens the Recently Deleted guide. Refuses if a removal
    /// would take every copy, or if a kept copy has left the library. Returns nil
    /// on success, or why nothing changed.
    @discardableResult
    func removeJunk(_ remove: Set<MediaItem.ID>, keeping keepers: Set<MediaItem.ID>) async -> PhotoChangeError? {
        if let refusal = await checkJunkRemoval(remove, keeping: keepers) { return refusal }
        return await delete(approved: remove)
    }

    /// One-tap Photo Cleanup: removes the approved duplicates and junk (with
    /// the same checks as `removeJunk`), then turns the approved Live Photos
    /// into stills, and opens one guide for both. If the removal worked but
    /// the stills didn't, the guide still opens for what was removed.
    @discardableResult
    func cleanUpPhotos(_ plan: PhotoCleanupPlan) async -> PhotoChangeError? {
        if !plan.remove.isEmpty, let refusal = await checkJunkRemoval(plan.remove, keeping: plan.keepers) { return refusal }
        let convert = plan.convert.subtracting(plan.remove)
        return await change(plan.remove.union(convert)) { changes in
            var receipt: DeletionReceipt?
            if !plan.remove.isEmpty { receipt = try await changes.delete(plan.remove) }
            var stills: [StillConversion] = []
            if !convert.isEmpty {
                do {
                    stills = try await changes.convertLivePhotosToStills(convert)
                } catch {
                    // Nothing changed yet: report it as usual.
                    guard receipt != nil else { throw error }
                    self.errorMessage = "Removed the duplicates and junk, but couldn't turn the Live Photos into stills: \(error.localizedDescription)"
                }
            }
            let removed = Array(receipt?.deleted ?? []) + stills.map(\.originalID)
            let bytes = (receipt?.deletedBytes ?? 0) + stills.reduce(Int64(0)) { $0 + $1.savedBytes }
            return CleanupGuide(kind: .photoCleanup(receipt, stills), removedIDs: removed, expectedBytes: bytes)
        }
    }

    /// Why a duplicates-and-junk removal must not go ahead, or nil if it can.
    private func checkJunkRemoval(_ remove: Set<MediaItem.ID>, keeping keepers: Set<MediaItem.ID>) async -> PhotoChangeError? {
        guard let junkReport else { return .junkChanged("Nothing has been found yet.") }
        do {
            try junkReport.validate(remove: remove, keepers: keepers)
        } catch let error as PhotoChangeError {
            return error
        } catch {
            return .verificationFailed(error.localizedDescription)
        }
        // A kept copy that left the library means removing the others could lose the photo.
        if !keepers.isEmpty {
            switch await albumCheck(keepers) {
            case .success(let check) where !check.missing.isEmpty:
                return .junkChanged("A copy you chose to keep is no longer in your library.")
            case .failure(let error):
                return error
            case .success:
                break
            }
        }
        return nil
    }

    // MARK: Changes (approved items only)

    /// Like `safetyCheck`, but a failed check comes back as its result, so a
    /// screen can mark the items it can't touch instead of only showing an error.
    func albumCheck(_ ids: Set<MediaItem.ID>) async -> Result<SafetyCheck, PhotoChangeError> {
        switch await safetyCheck(ids) {
        case .failure(.unsafe(let check)): .success(check)
        case let other: other
        }
    }

    /// Checks the approved items against the library without changing anything.
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

    /// Replaces the approved PNG screenshots with smaller HEIC copies, then
    /// opens the guide, since the PNGs wait in Recently Deleted. Returns nil on
    /// success, or why nothing changed.
    @discardableResult
    func resaveScreenshots(approved: Set<MediaItem.ID>) async -> PhotoChangeError? {
        await change(approved) { changes in
            let receipt = try await changes.resaveScreenshots(approved)
            return CleanupGuide(kind: .resavedScreenshots(receipt), removedIDs: receipt.resaved.map(\.originalID),
                                expectedBytes: receipt.savedBytes)
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

    /// Where "shrink all at once" is: how many copies are made out of how many.
    private(set) var videoBatchProgress: (done: Int, total: Int)?

    /// "Shrink all at once": makes a smaller full-length copy of each approved
    /// video at its quality, one at a time, then swaps every copy that came out
    /// clearly smaller in one Photos change (one iOS prompt), then opens the
    /// guide. Videos whose copy wouldn't save space are left alone. Returns nil
    /// on success, or why nothing changed.
    @discardableResult
    func shrinkVideos(_ qualities: [MediaItem.ID: VideoQuality]) async -> PhotoChangeError? {
        let videos = shrinkableVideos.filter { qualities[$0.id] != nil }
        guard !videos.isEmpty else { return .unsafe(SafetyCheck(approved: [])) }
        videoBatchProgress = (0, videos.count)
        defer { videoBatchProgress = nil }
        return await change(Set(videos.map(\.id))) { changes in
            var prepared: [PreparedVideo] = []
            var skipped = 0
            var failure: PhotoChangeError?
            do {
                for (index, item) in videos.enumerated() {
                    self.videoBatchProgress = (index, videos.count)
                    try Task.checkCancellation()
                    let edit = VideoEdit(quality: qualities[item.id] ?? .sameQuality, trim: .full(item.duration ?? 0))
                    do {
                        prepared.append(try await changes.prepareVideo(item.id, edit: edit))
                    } catch PhotoChangeError.videoNotSmaller {
                        skipped += 1
                    } catch PhotoChangeError.videoUnsupported {
                        skipped += 1
                    } catch let error as PhotoChangeError {
                        // One video that can't be copied (no space left, or it couldn't
                        // be fetched from iCloud) doesn't stop the ones already made.
                        guard case .exportFailed = error else { throw error }
                        failure = error
                        skipped += 1
                    }
                }
                self.videoBatchProgress = (videos.count, videos.count)
                guard !prepared.isEmpty else { throw failure ?? PhotoChangeError.videoNotSmaller }
                let results = try await changes.replaceVideos(with: prepared)
                return CleanupGuide(
                    kind: .shrunkVideos(results, skipped: skipped),
                    removedIDs: results.map(\.originalID),
                    expectedBytes: results.reduce(Int64(0)) { $0 + $1.originalBytes }
                )
            } catch {
                for copy in prepared { await changes.discard(copy) }
                throw error
            }
        }
    }

    private func change(
        _ approved: Set<MediaItem.ID>,
        _ work: (any PhotoChangeService) async throws -> CleanupGuide
    ) async -> PhotoChangeError? {
        guard !approved.isEmpty else { return .unsafe(SafetyCheck(approved: [])) }
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
            // Re-read the library so the Library tab shows what's really there now.
            await scanLibrary()
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
    func checkReclaim(readings: Int = 15, every interval: Duration = .seconds(2)) async {
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
        (model.libraryScan, model.lists) = organize(items)
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

/// What each tool works on in one scan, sorted and totalled once.
struct LibraryLists: Sendable {
    var ids: Set<MediaItem.ID> = []
    var convertibleLivePhotos: [MediaItem] = []
    var resavableScreenshots: [MediaItem] = []
    var bursts: [Burst] = []
    var shrinkableVideos: [MediaItem] = []
    var videoCount = 0
    var livePhotoSaving: Int64 = 0
    var screenshotSaving: Int64 = 0
    var burstSaving: Int64 = 0
    var videoSaving: Int64 = 0

    init() {}

    init(_ scan: LibraryScan) {
        var burstShots: [MediaItem] = []
        ids.reserveCapacity(scan.items.count)
        for item in scan.items {
            ids.insert(item.id)
            if item.isConvertibleLivePhoto {
                convertibleLivePhotos.append(item)
                livePhotoSaving += item.livePhotoVideoBytes
            }
            if ScreenshotResave.isResavable(item) {
                resavableScreenshots.append(item)
                screenshotSaving += ScreenshotResave.estimatedSaving(for: item)
            }
            if item.burstID != nil { burstShots.append(item) }
            if item.category == .video {
                videoCount += 1
                if item.isShrinkableVideo {
                    shrinkableVideos.append(item)
                    videoSaving += VideoShrink.estimatedSaving(for: item, edit: VideoEdit(quality: .smaller, trim: .full(item.duration ?? 0)))
                }
            }
        }
        // Biggest first, with the ID as a tie-breaker so the order is stable.
        resavableScreenshots.sort { ($0.currentBytes, $1.id) > ($1.currentBytes, $0.id) }
        shrinkableVideos.sort { ($0.currentBytes, $1.id) > ($1.currentBytes, $0.id) }
        bursts = Burst.all(in: burstShots)
        burstSaving = bursts.reduce(Int64(0)) { $0 + $1.savedBytes(keeping: $1.suggestedKeeper) }
    }
}
