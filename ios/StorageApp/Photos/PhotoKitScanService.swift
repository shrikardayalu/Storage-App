import Foundation
import Photos
import PhotosUI
import StorageCore
import UIKit

/// Reads one album from the real photo library and maps each asset onto
/// `MediaItem`. Read-only: nothing in this file changes Photos. The only
/// changes live in `TestAlbumChanges.swift`; `Tools/check-no-device-access.sh`
/// enforces both, and that Photos code stays in this folder.
struct PhotoKitScanService: PhotoScanService {
    func access() async -> PhotoAccess {
        Self.map(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    func requestAccess() async -> PhotoAccess {
        // Reading needs the .readWrite level; .addOnly can't see albums.
        Self.map(await PHPhotoLibrary.requestAuthorization(for: .readWrite))
    }

    func scanAlbum(named albumName: String) async throws -> [MediaItem] {
        let access = await access()
        guard access.canRead else { throw PhotoScanError.accessDenied }
        // Fetching sizes touches every asset's resources, so keep it off the main thread.
        return try await Task.detached(priority: .userInitiated) {
            try Self.read(albumName: albumName, limited: access == .limited)
        }.value
    }

    /// With full access, reads only the named album. With limited access iOS
    /// hides albums entirely, so it reads the photos the person picked; those
    /// are all the app can see anyway.
    private static func read(albumName: String, limited: Bool) throws -> [MediaItem] {
        let assetOptions = PHFetchOptions()
        // Every shot in a burst, not just the one Photos shows.
        assetOptions.includeAllBurstAssets = true

        let assets: PHFetchResult<PHAsset>
        if limited {
            assets = PHAsset.fetchAssets(with: assetOptions)
        } else {
            // The same lookup changes use, so a scan and a delete always mean one album.
            let album: PHAssetCollection
            do {
                album = try TestAlbum.resolve()
            } catch PhotoChangeError.albumAmbiguous(let name) {
                throw PhotoScanError.albumAmbiguous(name)
            } catch {
                throw PhotoScanError.albumNotFound(albumName)
            }
            assets = PHAsset.fetchAssets(in: album, options: assetOptions)
        }

        var items: [MediaItem] = []
        items.reserveCapacity(assets.count)
        assets.enumerateObjects { asset, _, _ in
            if let item = makeItem(from: asset) {
                items.append(item)
            }
        }
        return items
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
        let bytes = resources.reduce(Int64(0)) { $0 + TestAlbum.fileSize(of: $1) }
        let pairedVideoBytes = resources
            .filter { [.pairedVideo, .fullSizePairedVideo, .adjustmentBasePairedVideo].contains($0.type) }
            .reduce(Int64(0)) { $0 + TestAlbum.fileSize(of: $1) }
        let primary = resources.first { [.photo, .video, .fullSizePhoto, .fullSizeVideo].contains($0.type) } ?? resources.first
        let duration = category == .video ? asset.duration : nil

        var traits: MediaTraits = []
        if asset.mediaSubtypes.contains(.photoLive) { traits.insert(.livePhoto) }
        if asset.mediaSubtypes.contains(.videoHighFrameRate) { traits.insert(.slowMotion) }
        if asset.mediaSubtypes.contains(.videoCinematic) { traits.insert(.cinematic) }
        if asset.burstIdentifier != nil, !asset.burstSelectionTypes.isDisjoint(with: [.userPick, .autoPick]) {
            traits.insert(.burstPick)
        }

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
    /// was deleted after it's gone from the album.
    private static let cache = NSCache<NSString, UIImage>()

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
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject else {
            return nil
        }
        let options = PHImageRequestOptions()
        // One callback, and never downloads originals from iCloud.
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false
        let scale = await UIScreen.main.scale
        let size = CGSize(width: side * scale, height: side * scale)
        return await withCheckedContinuation { continuation in
            manager.requestImage(for: asset, targetSize: size, contentMode: .aspectFill, options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}
