import AVFoundation
import CoreLocation
import Foundation
import ImageIO
import Photos
import StorageCore
import UniformTypeIdentifiers

/// The only code in the app that changes the photo library, and it can only
/// reach the "Storage App Test" album. `Tools/check-no-device-access.sh`
/// enforces that change APIs appear nowhere else, and that this file never
/// fetches assets library-wide or by ID: every asset it changes comes out of
/// the album's own fetch result.
///
/// Every change runs the same gate first, fresh, right before changing anything:
/// 1. Full Photos access (limited access hides albums, so membership can't be confirmed).
/// 2. Exactly one user album with the test album's name.
/// 3. Every approved item is in that album, and in no other album the person made.
/// If any item fails, nothing changes. iOS then shows its own confirmation, and
/// afterwards the album is re-read to confirm only the approved items changed.
struct PhotoKitTestAlbumChanges: TestAlbumChangeService {
    func check(_ approved: Set<MediaItem.ID>) async throws -> SafetyCheck {
        try await Task.detached(priority: .userInitiated) {
            try Gate.open(approved).check
        }.value
    }

    func delete(_ approved: Set<MediaItem.ID>) async throws -> DeletionReceipt {
        let gate = try await Task.detached(priority: .userInitiated) { try Gate.open(approved) }.value
        let toDelete = gate.approvedAssets
        let bytes = toDelete.reduce(Int64(0)) { $0 + Self.bytes(of: $1) }

        try await Self.perform {
            PHAssetChangeRequest.deleteAssets(toDelete as NSArray)
        }

        let after = try TestAlbum.memberIDs(of: gate.album)
        let receipt = DeletionReceipt.audit(approved: approved, before: gate.memberIDs, after: after, deletedBytes: bytes)
        guard receipt.onlyApprovedRemoved else {
            throw PhotoChangeError.verificationFailed(
                "The album changed in an unexpected way: it went from \(receipt.albumCountBefore) to \(receipt.albumCountAfter) items. Scan again to see what's there."
            )
        }
        return receipt
    }

    func convertLivePhotosToStills(_ approved: Set<MediaItem.ID>) async throws -> [StillConversion] {
        let gate = try await Task.detached(priority: .userInitiated) { try Gate.open(approved) }.value
        let originals = gate.approvedAssets
        let notLive = originals.filter { !$0.mediaSubtypes.contains(.photoLive) || $0.burstIdentifier != nil }.count
        guard notLive == 0 else { throw PhotoChangeError.notLivePhoto(count: notLive) }

        // Read every still image before changing anything, so a failed read changes nothing.
        var stills: [(original: PHAsset, data: Data, filename: String)] = []
        for asset in originals {
            stills.append(try await Self.stillImage(of: asset))
        }

        let album = gate.album
        let created = Box<[String: String]>([:]) // original ID -> new still's ID
        try await Self.perform {
            var placeholders: [PHObjectPlaceholder] = []
            for still in stills {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = still.filename
                request.addResource(with: .photo, data: still.data, options: options)
                // The details people care about. EXIF inside the image data is kept as is.
                request.creationDate = still.original.creationDate
                request.location = still.original.location
                request.isFavorite = still.original.isFavorite
                request.isHidden = still.original.isHidden
                if let placeholder = request.placeholderForCreatedAsset {
                    placeholders.append(placeholder)
                    created.value[still.original.localIdentifier] = placeholder.localIdentifier
                }
            }
            PHAssetCollectionChangeRequest(for: album)?.addAssets(placeholders as NSArray)
            // In the same change, so declining iOS's prompt leaves no copies behind.
            PHAssetChangeRequest.deleteAssets(originals as NSArray)
        }

        // Re-read the album and compare each still with its original.
        let members = TestAlbum.assets(in: album)
        var byID: [String: PHAsset] = [:]
        members.enumerateObjects { asset, _, _ in byID[asset.localIdentifier] = asset }

        var results: [StillConversion] = []
        for original in originals {
            guard let stillID = created.value[original.localIdentifier] else { continue }
            let still = byID[stillID]
            results.append(StillConversion(
                originalID: original.localIdentifier,
                stillID: stillID,
                original: Self.details(of: original, inAlbum: true),
                still: still.map { Self.details(of: $0, inAlbum: true) } ?? Self.missing,
                savedBytes: Self.pairedVideoBytes(of: original)
            ))
        }
        let originalsLeft = originals.filter { byID[$0.localIdentifier] != nil }.count
        guard results.count == originals.count, originalsLeft == 0 else {
            throw PhotoChangeError.verificationFailed("Some photos didn't convert. Scan again to see what's there.")
        }
        return results
    }

    func resaveScreenshots(_ approved: Set<MediaItem.ID>) async throws -> ScreenshotResaveReceipt {
        let gate = try await Task.detached(priority: .userInitiated) { try Gate.open(approved) }.value
        let originals = gate.approvedAssets
        let notPNG = originals.filter { !Self.isPNGScreenshot($0) }.count
        guard notPNG == 0 else { throw PhotoChangeError.notResavable(count: notPNG) }

        // Encode every copy before changing anything, so a failed read changes
        // nothing, and keep only the ones that come out clearly smaller.
        var copies: [(original: PHAsset, data: Data, filename: String, originalBytes: Int64)] = []
        var skipped = Set<String>()
        for asset in originals {
            let source = try await Self.stillImage(of: asset)
            let originalBytes = Self.bytes(of: asset)
            let heic = try Self.heicCopy(of: source.data)
            if ScreenshotResave.isWorthReplacing(originalBytes: originalBytes, newBytes: Int64(heic.count)) {
                let name = (source.filename as NSString).deletingPathExtension + ".HEIC"
                copies.append((asset, heic, name, originalBytes))
            } else {
                skipped.insert(asset.localIdentifier)
            }
        }
        guard !copies.isEmpty else { throw PhotoChangeError.screenshotsNotSmaller }

        let album = gate.album
        let created = Box<[String: String]>([:]) // original ID -> copy's ID
        try await Self.perform {
            var placeholders: [PHObjectPlaceholder] = []
            for copy in copies {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = copy.filename
                request.addResource(with: .photo, data: copy.data, options: options)
                request.creationDate = copy.original.creationDate
                request.location = copy.original.location
                request.isFavorite = copy.original.isFavorite
                request.isHidden = copy.original.isHidden
                if let placeholder = request.placeholderForCreatedAsset {
                    placeholders.append(placeholder)
                    created.value[copy.original.localIdentifier] = placeholder.localIdentifier
                }
            }
            PHAssetCollectionChangeRequest(for: album)?.addAssets(placeholders as NSArray)
            // In the same change, so declining iOS's prompt leaves no copies behind.
            PHAssetChangeRequest.deleteAssets(copies.map(\.original) as NSArray)
        }

        // Re-read the album and compare each copy with its original.
        var byID: [String: PHAsset] = [:]
        TestAlbum.assets(in: album).enumerateObjects { asset, _, _ in byID[asset.localIdentifier] = asset }
        var resaved: [ResavedScreenshot] = []
        for copy in copies {
            guard let newID = created.value[copy.original.localIdentifier] else { continue }
            let new = byID[newID]
            let newBytes = new.map(Self.bytes(of:)) ?? 0
            resaved.append(ResavedScreenshot(
                originalID: copy.original.localIdentifier,
                newID: newID,
                original: Self.details(of: copy.original, inAlbum: true),
                new: new.map { Self.details(of: $0, inAlbum: true) } ?? Self.missing,
                originalBytes: copy.originalBytes,
                // Photos can take a moment to report a new file's size; the encoded size stands in until then.
                newBytes: newBytes > 0 ? newBytes : Int64(copy.data.count)
            ))
        }
        let originalsLeft = copies.filter { byID[$0.original.localIdentifier] != nil }.count
        guard resaved.count == copies.count, originalsLeft == 0 else {
            throw PhotoChangeError.verificationFailed("Some screenshots didn't re-save. Scan again to see what's there.")
        }
        return ScreenshotResaveReceipt(resaved: resaved, skipped: skipped)
    }

    func keepBurstPicks(keep: Set<MediaItem.ID>, remove: Set<MediaItem.ID>) async throws -> BurstReceipt {
        let (gate, plan, before) = try await Task.detached(priority: .userInitiated) {
            guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized else {
                throw PhotoChangeError.needsFullAccess
            }
            let album = try TestAlbum.resolve()
            let before = TestAlbum.burstMembers(of: album)
            // Worked out from the album as it is now, and refused unless it matches the review.
            let plan = try BurstPlan.make(keep: keep, expectedRemove: remove, members: before)
            return (try Gate.open(plan.remove), plan, before)
        }.value
        let toDelete = gate.approvedAssets
        let bytes = toDelete.reduce(Int64(0)) { $0 + Self.bytes(of: $1) }

        try await Self.perform {
            PHAssetChangeRequest.deleteAssets(toDelete as NSArray)
        }

        let after = TestAlbum.burstMembers(of: gate.album)
        let receipt = BurstReceipt.audit(plan: plan, before: before, after: after, removedBytes: bytes)
        guard receipt.isExact else {
            throw PhotoChangeError.verificationFailed(
                "The bursts didn't end up as picked: \(receipt.keptPick.count) of \(plan.keepers.count) have only your pick left. Scan again to see what's there."
            )
        }
        return receipt
    }

    func prepareVideo(_ id: MediaItem.ID, edit: VideoEdit) async throws -> PreparedVideo {
        let gate = try await Task.detached(priority: .userInitiated) { try Gate.open([id]) }.value
        guard let original = gate.approvedAssets.first, original.mediaType == .video else {
            throw PhotoChangeError.videoUnsupported("That item isn't a video any more.")
        }
        if original.mediaSubtypes.contains(.videoHighFrameRate) || original.mediaSubtypes.contains(.videoCinematic) {
            throw PhotoChangeError.videoUnsupported("Slo-mo and Cinematic videos are left alone.")
        }
        let originalBytes = Self.bytes(of: original)
        let copy = try await VideoExporter.export(try await Self.videoAsset(of: original), edit: edit)
        guard VideoShrink.isWorthReplacing(originalBytes: originalBytes, newBytes: copy.bytes) else {
            VideoExporter.remove(copy.url)
            throw PhotoChangeError.videoNotSmaller
        }
        return PreparedVideo(
            originalID: id, edit: edit, fileURL: copy.url, originalBytes: originalBytes,
            newBytes: copy.bytes, newDuration: copy.duration, sourceVersion: Self.version(of: original)
        )
    }

    func replaceVideo(with prepared: PreparedVideo) async throws -> VideoReplacement {
        let gate = try await Task.detached(priority: .userInitiated) { try Gate.open([prepared.originalID]) }.value
        guard let original = gate.approvedAssets.first, original.mediaType == .video,
              Self.version(of: original) == prepared.sourceVersion else {
            throw PhotoChangeError.videoUnsupported("The video changed since the smaller copy was made. Make it again.")
        }
        guard FileManager.default.fileExists(atPath: prepared.fileURL.path) else {
            throw PhotoChangeError.videoUnsupported("The smaller copy is gone. Make it again.")
        }
        let before = Self.videoDetails(of: original, bytes: prepared.originalBytes)
        let name = PHAssetResource.assetResources(for: original).first { $0.type == .video }?.originalFilename ?? "Video.MOV"

        let album = gate.album
        let created = Box<String?>(nil)
        try await Self.perform {
            let request = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()
            options.originalFilename = (name as NSString).deletingPathExtension + ".MOV"
            // Photos takes the copy over, so it isn't left in the temporary folder.
            options.shouldMoveFile = true
            request.addResource(with: .video, fileURL: prepared.fileURL, options: options)
            request.creationDate = original.creationDate
            request.location = original.location
            request.isFavorite = original.isFavorite
            request.isHidden = original.isHidden
            if let placeholder = request.placeholderForCreatedAsset {
                created.value = placeholder.localIdentifier
                PHAssetCollectionChangeRequest(for: album)?.addAssets([placeholder] as NSArray)
            }
            // In the same change, so declining iOS's prompt leaves no copy behind.
            PHAssetChangeRequest.deleteAssets([original] as NSArray)
        }

        // Re-read the album and compare the copy with the original.
        var byID: [String: PHAsset] = [:]
        TestAlbum.assets(in: album).enumerateObjects { asset, _, _ in byID[asset.localIdentifier] = asset }
        guard let newID = created.value, let copy = byID[newID] else {
            throw PhotoChangeError.verificationFailed(
                "The smaller copy didn't show up in the album. If the original is in Recently Deleted, recover it there."
            )
        }
        // Photos can take a moment to report a new file's size; the measured copy stands in until then.
        let copyBytes = Self.bytes(of: copy)
        return VideoReplacement(
            originalID: original.localIdentifier,
            newID: newID,
            edit: prepared.edit,
            original: before,
            new: Self.videoDetails(of: copy, bytes: copyBytes > 0 ? copyBytes : prepared.newBytes),
            originalGone: byID[original.localIdentifier] == nil
        )
    }

    func discard(_ prepared: PreparedVideo) async {
        VideoExporter.remove(prepared.fileURL)
    }

    // MARK: - The gate

    /// Everything a change needs, read fresh, and only if the safety check passed.
    private struct Gate {
        let album: PHAssetCollection
        let memberIDs: Set<String>
        /// The approved assets, taken from the album's own fetch result.
        let approvedAssets: [PHAsset]
        let check: SafetyCheck

        static func open(_ approved: Set<MediaItem.ID>) throws -> Gate {
            guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized else {
                throw PhotoChangeError.needsFullAccess
            }
            let album = try TestAlbum.resolve()
            let members = TestAlbum.assets(in: album)

            var memberIDs = Set<String>()
            var approvedAssets: [PHAsset] = []
            members.enumerateObjects { asset, _, _ in
                memberIDs.insert(asset.localIdentifier)
                if approved.contains(asset.localIdentifier) {
                    approvedAssets.append(asset)
                }
            }

            // Any other album the person made that also holds an approved item.
            var inOtherAlbums = Set<String>()
            for asset in approvedAssets {
                let albums = PHAssetCollection.fetchAssetCollectionsContaining(asset, with: .album, options: nil)
                albums.enumerateObjects { collection, _, stop in
                    if collection.localIdentifier != album.localIdentifier {
                        inOtherAlbums.insert(asset.localIdentifier)
                        stop.pointee = true
                    }
                }
            }

            let check = SafetyCheck.evaluate(approved: approved, testAlbumMembers: memberIDs, otherAlbumMembers: inOtherAlbums)
            guard check.isSafe else { throw PhotoChangeError.unsafe(check) }
            // Belt and braces: the assets to change are exactly the approved ones.
            guard Set(approvedAssets.map(\.localIdentifier)) == approved else {
                throw PhotoChangeError.unsafe(check)
            }
            return Gate(album: album, memberIDs: memberIDs, approvedAssets: approvedAssets, check: check)
        }
    }

    // MARK: - Helpers

    /// Runs one change. iOS asks the person to confirm deletions; declining throws `.cancelled`.
    private static func perform(_ changes: @escaping () -> Void) async throws {
        do {
            try await PHPhotoLibrary.shared().performChanges(changes)
        } catch let error as NSError {
            let declined = (error.domain == PHPhotosErrorDomain && error.code == PHPhotosError.userCancelled.rawValue)
                // Cocoa's "user cancelled", which some iOS versions return instead.
                || (error.domain == NSCocoaErrorDomain && error.code == NSUserCancelledError)
            throw declined ? PhotoChangeError.cancelled : error
        }
    }

    /// The photo exactly as Photos shows it: the edited version if there is one,
    /// otherwise the original, with its EXIF untouched.
    private static func stillImage(of asset: PHAsset) async throws -> (original: PHAsset, data: Data, filename: String) {
        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = resources.first(where: { $0.type == .fullSizePhoto }) ?? resources.first(where: { $0.type == .photo }) else {
            throw PhotoChangeError.verificationFailed("A Live Photo had no still image to keep. Nothing was changed.")
        }
        let original = resources.first { $0.type == .photo }?.originalFilename ?? resource.originalFilename
        let options = PHAssetResourceRequestOptions()
        // Fetches the full photo from iCloud if only a preview is on the phone.
        options.isNetworkAccessAllowed = true
        let data = Box(Data())
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHAssetResourceManager.default().requestData(for: resource, options: options) { chunk in
                data.value.append(chunk)
            } completionHandler: { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
        return (asset, data.value, original)
    }

    /// A screenshot whose original file is still a PNG.
    private static func isPNGScreenshot(_ asset: PHAsset) -> Bool {
        guard asset.mediaType == .image, asset.mediaSubtypes.contains(.photoScreenshot), asset.burstIdentifier == nil else { return false }
        return PHAssetResource.assetResources(for: asset).first { $0.type == .photo }?.uniformTypeIdentifier == UTType.png.identifier
    }

    /// The same image as high-quality HEIC, same pixel size, with the PNG's
    /// metadata (including the tag that marks it as a screenshot) carried over.
    private static func heicCopy(of png: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw PhotoChangeError.verificationFailed("A screenshot couldn't be read. Nothing was changed.")
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.heic.identifier as CFString, 1, nil) else {
            throw PhotoChangeError.verificationFailed("This iPhone can't save HEIC images. Nothing was changed.")
        }
        var properties = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
        properties[kCGImageDestinationLossyCompressionQuality] = ScreenshotResave.quality
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw PhotoChangeError.verificationFailed("A screenshot couldn't be re-saved. Nothing was changed.")
        }
        return output as Data
    }

    private static func details(of asset: PHAsset, inAlbum: Bool) -> AssetDetails {
        AssetDetails(
            creationDate: asset.creationDate,
            latitude: asset.location?.coordinate.latitude,
            longitude: asset.location?.coordinate.longitude,
            isFavorite: asset.isFavorite,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            isLivePhoto: asset.mediaSubtypes.contains(.photoLive),
            inTestAlbum: inAlbum
        )
    }

    /// Stands in for a still that wasn't found in the album afterwards, so every check fails.
    private static let missing = AssetDetails(
        creationDate: nil, latitude: nil, longitude: nil, isFavorite: false,
        pixelWidth: 0, pixelHeight: 0, isLivePhoto: true, inTestAlbum: false
    )

    /// The video as Photos plays it, including any edits. Downloads it from iCloud if needed.
    private static func videoAsset(of asset: PHAsset) async throws -> AVAsset {
        let options = PHVideoRequestOptions()
        options.version = .current
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        return try await withCheckedThrowingContinuation { continuation in
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { video, _, info in
                if let video {
                    continuation.resume(returning: video)
                } else {
                    let detail = (info?[PHImageErrorKey] as? Error)?.localizedDescription ?? "Photos couldn't open the video."
                    continuation.resume(throwing: PhotoChangeError.exportFailed(detail))
                }
            }
        }
    }

    /// Changes whenever the video itself is edited, so a copy made before an edit is refused.
    private static func version(of asset: PHAsset) -> String {
        "\(asset.duration)-\(bytes(of: asset))"
    }

    private static func videoDetails(of asset: PHAsset, bytes: Int64) -> VideoDetails {
        VideoDetails(
            creationDate: asset.creationDate,
            latitude: asset.location?.coordinate.latitude,
            longitude: asset.location?.coordinate.longitude,
            isFavorite: asset.isFavorite,
            duration: asset.duration,
            bytes: bytes,
            isVideo: asset.mediaType == .video,
            inTestAlbum: true
        )
    }

    private static func bytes(of asset: PHAsset) -> Int64 {
        PHAssetResource.assetResources(for: asset).reduce(Int64(0)) { $0 + TestAlbum.fileSize(of: $1) }
    }

    private static func pairedVideoBytes(of asset: PHAsset) -> Int64 {
        PHAssetResource.assetResources(for: asset)
            .filter { [.pairedVideo, .fullSizePairedVideo, .adjustmentBasePairedVideo].contains($0.type) }
            .reduce(Int64(0)) { $0 + TestAlbum.fileSize(of: $1) }
    }
}

/// Finds the test album. Shared by the scan and by changes, so both always
/// mean the same album.
enum TestAlbum {
    /// The one user-made album named `TestMode.albumName`. Throws if there are none or several.
    static func resolve() throws -> PHAssetCollection {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "localizedTitle == %@", TestMode.albumName)
        let albums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: options)
        guard albums.count > 0, let album = albums.firstObject else { throw PhotoChangeError.albumNotFound(TestMode.albumName) }
        guard albums.count == 1 else { throw PhotoChangeError.albumAmbiguous(TestMode.albumName) }
        return album
    }

    /// Every asset in `album`, including each shot of a burst.
    static func assets(in album: PHAssetCollection) -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.includeAllBurstAssets = true
        return PHAsset.fetchAssets(in: album, options: options)
    }

    /// Every item in `album` with its burst ID, nil for items not in a burst.
    static func burstMembers(of album: PHAssetCollection) -> [String: String?] {
        var members: [String: String?] = [:]
        assets(in: album).enumerateObjects { asset, _, _ in members[asset.localIdentifier] = .some(asset.burstIdentifier) }
        return members
    }

    static func memberIDs(of album: PHAssetCollection) throws -> Set<String> {
        var ids = Set<String>()
        assets(in: album).enumerateObjects { asset, _, _ in ids.insert(asset.localIdentifier) }
        return ids
    }

    /// PhotoKit has no public size API. `fileSize` is the size the resource
    /// takes (or would take, if it's only in iCloud); 0 when unavailable.
    static func fileSize(of resource: PHAssetResource) -> Int64 {
        (resource.value(forKey: "fileSize") as? NSNumber)?.int64Value ?? 0
    }
}

/// A mutable box for values filled in from PhotoKit callbacks.
private final class Box<Value>: @unchecked Sendable {
    var value: Value
    init(_ value: Value) { self.value = value }
}
