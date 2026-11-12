import Foundation
import Photos
import PhotosUI
import StorageCore
import UIKit

/// Reads the real photo library and maps each asset onto `MediaItem`.
/// Read-only: nothing in this file changes Photos. The only changes live in
/// `PhotoLibraryChanges.swift`; `Tools/check-no-device-access.sh` enforces
/// both, and that Photos code stays in this folder.
struct PhotoKitScanService: PhotoScanService {
    func access() async -> PhotoAccess {
        Self.map(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    func requestAccess() async -> PhotoAccess {
        // Reading needs the .readWrite level; .addOnly can't see what's there.
        Self.map(await PHPhotoLibrary.requestAuthorization(for: .readWrite))
    }

    func scanLibrary() async throws -> [MediaItem] {
        guard await access().canRead else { throw PhotoScanError.accessDenied }
        // Fetching sizes touches every asset's resources, so keep it off the main thread.
        return await Task.detached(priority: .userInitiated) { Self.read() }.value
    }

    func lastScan() async -> [MediaItem]? {
        guard await access().canRead else { return nil }
        return await Task.detached(priority: .userInitiated) {
            let saved = ScanCache.load()
            return saved.isEmpty ? nil : saved.map(\.item)
        }.value
    }

    /// Every photo and video the app may see: the whole library with full
    /// access, or the photos the person picked with limited access.
    private static func read() -> [MediaItem] {
        var assets: [PHAsset] = []
        let all = PhotoLibrary.allAssets()
        assets.reserveCapacity(all.count)
        all.enumerateObjects { asset, _, _ in assets.append(asset) }
        guard !assets.isEmpty else {
            ScanCache.save([])
            return []
        }

        // Reading each asset's file sizes is the slow part of a scan: tens of
        // seconds for a library of tens of thousands. So what the last scan
        // read is kept, and only items that are new or changed since are read again.
        let saved = ScanCache.load()
        let known = Dictionary(saved.map { ($0.item.id, $0) }, uniquingKeysWith: { first, _ in first })

        let workers = max(1, min(ProcessInfo.processInfo.activeProcessorCount, 4))
        let slice = (assets.count + workers - 1) / workers
        let parts = Parts(count: workers)
        DispatchQueue.concurrentPerform(iterations: workers) { worker in
            let from = worker * slice
            let to = min(assets.count, from + slice)
            guard from < to else { return }
            var entries: [ScanCache.Entry] = []
            entries.reserveCapacity(to - from)
            var fresh = 0
            for index in from..<to {
                autoreleasepool {
                    let asset = assets[index]
                    if let hit = known[asset.localIdentifier], ScanCache.same(hit.modified, asset.modificationDate) {
                        entries.append(hit)
                    } else if let item = makeItem(from: asset) {
                        entries.append(ScanCache.Entry(item: item, modified: asset.modificationDate))
                        fresh += 1
                    }
                }
            }
            parts.set(entries, fresh: fresh, at: worker)
        }
        let (entries, fresh) = parts.joined()
        if fresh > 0 || entries.count != saved.count {
            // Off to the side, so the scan's result isn't held up by the save.
            Task.detached(priority: .utility) { ScanCache.save(entries) }
        }
        return entries.map(\.item)
    }

    /// Collects each worker's items, in order, and how many had to be read from Photos.
    private final class Parts: @unchecked Sendable {
        private let lock = NSLock()
        private var parts: [[ScanCache.Entry]]
        private var fresh = 0

        init(count: Int) { parts = Array(repeating: [], count: count) }

        func set(_ entries: [ScanCache.Entry], fresh count: Int, at index: Int) {
            lock.lock()
            parts[index] = entries
            fresh += count
            lock.unlock()
        }

        func joined() -> ([ScanCache.Entry], fresh: Int) {
            lock.lock()
            defer { lock.unlock() }
            return (parts.flatMap { $0 }, fresh)
        }
    }

    private static func makeItem(from asset: PHAsset) -> MediaItem? {
        let category: MediaCategory
        switch asset.mediaType {
        case .image:
            category = asset.mediaSubtypes.contains(.photoScreenshot) ? .screenshot : .photo
        case .video:
            category = .video
        default:
            return nil
        }

        let resources = PHAssetResource.assetResources(for: asset)
        // A Live Photo's paired video and any saved edits take space too, so count every resource.
        let bytes = resources.reduce(Int64(0)) { $0 + PhotoLibrary.fileSize(of: $1) }
        let pairedVideoBytes = resources
            .filter { [.pairedVideo, .fullSizePairedVideo, .adjustmentBasePairedVideo].contains($0.type) }
            .reduce(Int64(0)) { $0 + PhotoLibrary.fileSize(of: $1) }
        let primary = resources.first { [.photo, .video, .fullSizePhoto, .fullSizeVideo].contains($0.type) } ?? resources.first
        let duration = category == .video ? asset.duration : nil

        var traits: MediaTraits = []
        if asset.mediaSubtypes.contains(.photoLive) { traits.insert(.livePhoto) }
        if asset.mediaSubtypes.contains(.videoHighFrameRate) { traits.insert(.slowMotion) }
        if asset.mediaSubtypes.contains(.videoCinematic) { traits.insert(.cinematic) }
        if asset.burstIdentifier != nil, !asset.burstSelectionTypes.isDisjoint(with: [.userPick, .autoPick]) {
            traits.insert(.burstPick)
        }
        // Signs someone cares about it: never suggested as junk.
        if asset.isFavorite { traits.insert(.favorite) }
        if resources.contains(where: { $0.type == .adjustmentData }) { traits.insert(.edited) }

        return MediaItem(
            id: asset.localIdentifier,
            category: category,
            format: format(of: primary, category: category, bytes: bytes, duration: duration),
            filename: primary?.originalFilename ?? "Untitled",
            creationDate: asset.creationDate ?? .distantPast,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            duration: duration,
            originalBytes: bytes,
            thumbnailSeed: UInt32(truncatingIfNeeded: asset.localIdentifier.hashValue),
            traits: traits,
            burstID: asset.burstIdentifier,
            livePhotoVideoBytes: traits.contains(.livePhoto) ? pairedVideoBytes : 0
        )
    }

    private static func format(of resource: PHAssetResource?, category: MediaCategory, bytes: Int64, duration: TimeInterval?) -> MediaFormat {
        let type = resource?.uniformTypeIdentifier ?? ""
        if category == .video {
            // Codec isn't exposed without decoding the file. ProRes runs at
            // hundreds of megabits per second; HEVC and H.264 stay far below that.
            if let duration, duration > 0, Double(bytes) * 8 / duration > 150_000_000 {
                return .proRes
            }
            return type == "public.mpeg-4" ? .h264 : .hevc
        }
        switch type {
        case "com.adobe.raw-image": return .proRAW
        case "public.png": return .png
        case "public.jpeg": return .jpeg
        default: return .heic
        }
    }

    private static func map(_ status: PHAuthorizationStatus) -> PhotoAccess {
        switch status {
        case .authorized: .granted
        case .limited: .limited
        case .notDetermined: .notDetermined
        default: .denied
        }
    }
}

/// What the last scan read about each item, kept in the app's caches folder so
/// the next launch can show the library at once and re-read only what changed.
/// It's a cache: losing it only means a full scan, and nothing in it leaves
/// the phone. Changes never trust it; they look every item up in Photos first.
enum ScanCache {
    struct Entry: Codable, Sendable {
        let item: MediaItem
        /// When Photos last saw the item change. A different date means read it again.
        let modified: Date?
    }

    private struct File: Codable {
        /// Bumped whenever what a scan reads about an item changes, so old files are dropped.
        var version = ScanCache.version
        var entries: [Entry]
    }

    /// 2: items carry the favorite and edited traits.
    private static let version = 2
    private static let lock = NSLock()
    /// Kept after the first decode, so a rescan doesn't read the file again.
    private static var memory: [Entry]?
    private static var fileURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("library-scan.plist")
    }

    static func load() -> [Entry] {
        lock.lock()
        defer { lock.unlock() }
        if let memory { return memory }
        guard let fileURL, let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe),
              let file = try? PropertyListDecoder().decode(File.self, from: data), file.version == version else {
            memory = []
            return []
        }
        memory = file.entries
        return file.entries
    }

    static func save(_ entries: [Entry]) {
        lock.lock()
        defer { lock.unlock() }
        memory = entries
        guard let fileURL else { return }
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        guard let data = try? encoder.encode(File(entries: entries)) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    static func same(_ a: Date?, _ b: Date?) -> Bool {
        switch (a, b) {
        case (nil, nil): true
        case let (a?, b?): abs(a.timeIntervalSince(b)) < 0.001
        default: false
        }
    }
}

/// Shows the system sheet for changing which photos a limited-access app can
/// see. Returns once the person closes it.
enum LimitedPhotoPicker {
    @MainActor
    static func present() async {
        let scene = UIApplication.shared.connectedScenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
        guard var controller = scene?.keyWindow?.rootViewController else { return }
        while let presented = controller.presentedViewController {
            controller = presented
        }
        _ = await PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: controller)
    }
}

/// Loads a small thumbnail for a scanned item from Photos.
enum PhotoThumbnailLoader {
    private static let manager = PHCachingImageManager()
    /// Recent thumbnails, so the Recently Deleted guide can still show what
    /// was deleted after it's gone from the library.
    /// Bounded, because a library can hold tens of thousands of photos.
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 600
        return cache
    }()

    /// A thumbnail already loaded this session, if any. Never touches Photos.
    static func cached(_ localIdentifier: String) -> UIImage? {
        cache.object(forKey: localIdentifier as NSString)
    }

    static func image(for localIdentifier: String, side: CGFloat) async -> UIImage? {
        if let cached = cached(localIdentifier), cached.size.width * cached.scale >= side * 2 {
            return cached
        }
        let image = await load(localIdentifier, side: side)
        if let image { cache.setObject(image, forKey: localIdentifier as NSString) }
        return image
    }

    private static func load(_ localIdentifier: String, side: CGFloat) async -> UIImage? {
        guard let asset = PhotoLibrary.asset(localIdentifier) else { return nil }
        let options = PHImageRequestOptions()
        // One callback, and never downloads originals from iCloud.
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false
        let scale = await UIScreen.main.scale
        let size = CGSize(width: side * scale, height: side * scale)
        return await withCheckedContinuation { continuation in
            // PhotoKit can call back more than once; a second resume crashes.
            let once = Once()
            manager.requestImage(for: asset, targetSize: size, contentMode: .aspectFill, options: options) { image, _ in
                if once.first() { continuation.resume(returning: image) }
            }
        }
    }

    /// Resumes a continuation exactly once.
    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false

        func first() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !done else { return false }
            done = true
            return true
        }
    }
}

/// How the app finds things in the photo library. Read-only. Shared by the
/// scan and by changes, so both always see the library the same way.
enum PhotoLibrary {
    /// Every shot of a burst, not just the one Photos shows, and only what's
    /// in the person's own library (not shared albums or synced-from-a-computer photos,
    /// which can't be changed).
    static func options() -> PHFetchOptions {
        let options = PHFetchOptions()
        options.includeAllBurstAssets = true
        options.includeAssetSourceTypes = [.typeUserLibrary]
        return options
    }

    /// Every photo and video the app may see. Hidden and recently deleted items are left out.
    static func allAssets() -> PHFetchResult<PHAsset> {
        PHAsset.fetchAssets(with: options())
    }

    /// How many items the library holds right now.
    static func count() -> Int {
        allAssets().count
    }

    static func asset(_ id: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [id], options: options()).firstObject
    }

    /// The assets with these IDs that are in the library right now. IDs that
    /// are gone (deleted, or no longer shared with the app) are simply left out.
    static func assets(withIDs ids: Set<String>) -> [PHAsset] {
        guard !ids.isEmpty else { return [] }
        var found: [PHAsset] = []
        var seen = Set<String>()
        PHAsset.fetchAssets(withLocalIdentifiers: Array(ids), options: options()).enumerateObjects { asset, _, _ in
            if ids.contains(asset.localIdentifier), seen.insert(asset.localIdentifier).inserted { found.append(asset) }
        }
        if seen.count < ids.count {
            // Look once more the way the scan does, so an item the scan showed
            // is never reported missing just because of how it was looked up.
            allAssets().enumerateObjects { asset, _, stop in
                if ids.contains(asset.localIdentifier), seen.insert(asset.localIdentifier).inserted {
                    found.append(asset)
                    if seen.count == ids.count { stop.pointee = true }
                }
            }
        }
        return found
    }

    /// These assets and every other shot of the bursts they belong to, each
    /// with its burst ID (nil for an asset that isn't in a burst).
    static func burstMembers(with assets: [PHAsset]) -> [String: String?] {
        var members: [String: String?] = [:]
        var bursts = Set<String>()
        for asset in assets {
            members[asset.localIdentifier] = .some(asset.burstIdentifier)
            if let burst = asset.burstIdentifier { bursts.insert(burst) }
        }
        for burst in bursts {
            PHAsset.fetchAssets(withBurstIdentifier: burst, options: options()).enumerateObjects { asset, _, _ in
                members[asset.localIdentifier] = .some(burst)
            }
        }
        return members
    }

    /// The albums the person made that hold `asset` and can take a new item.
    /// Shared albums and albums synced from a computer are left out.
    static func userAlbums(containing asset: PHAsset) -> [PHAssetCollection] {
        var albums: [PHAssetCollection] = []
        PHAssetCollection.fetchAssetCollectionsContaining(asset, with: .album, options: nil).enumerateObjects { album, _, _ in
            if album.assetCollectionSubtype == .albumRegular, album.canPerform(.addContent) { albums.append(album) }
        }
        return albums
    }

    /// PhotoKit has no public size API. `fileSize` is the size the resource
    /// takes (or would take, if it's only in iCloud); 0 when unavailable.
    static func fileSize(of resource: PHAssetResource) -> Int64 {
        (resource.value(forKey: "fileSize") as? NSNumber)?.int64Value ?? 0
    }
}
