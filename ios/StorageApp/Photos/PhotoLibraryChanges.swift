import AVFoundation
import CoreLocation
import Foundation
import ImageIO
import Photos
import StorageCore
import UniformTypeIdentifiers

/// The only code in the app that changes the photo library.
/// `Tools/check-no-device-access.sh` enforces that change APIs appear nowhere
/// else, and that this file never fetches assets library-wide: every asset it
/// changes is looked up by the ID of an item the person approved.
///
/// Every change runs the same gate first, fresh, right before changing anything:
/// 1. Full Photos access (with limited access the app can't see albums, so a
///    copy couldn't be put back where its original was).
/// 2. Every approved item is still in the library.
/// If any item fails, nothing changes. iOS then shows its own confirmation, and
/// afterwards the library is re-read to confirm only the approved items changed.
///
/// Copies that replace an original (a still, a re-saved screenshot, a smaller
/// video) are written to the app's own temporary folder first, one at a time,
/// so a big cleanup never holds a library's worth of photos in memory. Each
/// copy keeps its original's date, location, favorite and albums.
struct PhotoKitChanges: PhotoChangeService {
    func check(_ approved: Set<MediaItem.ID>) async throws -> SafetyCheck {
        try await Task.detached(priority: .userInitiated) {
            try Gate.open(approved).check
        }.value
    }

    func delete(_ approved: Set<MediaItem.ID>) async throws -> DeletionReceipt {
        let (gate, countBefore) = try await Task.detached(priority: .userInitiated) {
            (try Gate.open(approved), PhotoLibrary.count())
        }.value
        let toDelete = gate.approvedAssets
        let bytes = toDelete.reduce(Int64(0)) { $0 + Self.bytes(of: $1) }

        try await Self.perform {
            PHAssetChangeRequest.deleteAssets(toDelete as NSArray)
        }

        let receipt = await Task.detached(priority: .userInitiated) {
            DeletionReceipt.audit(
                approved: approved,
                stillPresent: Set(PhotoLibrary.assets(withIDs: approved).map(\.localIdentifier)),
                countBefore: countBefore,
                countAfter: PhotoLibrary.count(),
                deletedBytes: bytes
            )
        }.value
        guard receipt.onlyApprovedRemoved else {
            throw PhotoChangeError.verificationFailed(
                "The library changed in an unexpected way: it went from \(receipt.countBefore) to \(receipt.countAfter) items. Scan again to see what's there."
            )
        }
        return receipt
    }

    func convertLivePhotosToStills(_ approved: Set<MediaItem.ID>) async throws -> [StillConversion] {
        let gate = try await Task.detached(priority: .userInitiated) { try Gate.open(approved) }.value
        let originals = gate.approvedAssets
        let notLive = originals.filter { !$0.mediaSubtypes.contains(.photoLive) || $0.burstIdentifier != nil }.count
        guard notLive == 0 else { throw PhotoChangeError.notLivePhoto(count: notLive) }

        // Write every still to a file before changing anything, so a failed read changes nothing.
        // The Live versions wait in Recently Deleted until it's emptied, so the
        // stills need room of their own: on a nearly full phone, only as many
        // as fit are converted now, and the rest stay as they are for next time.
        var stills: [Copy] = []
        var converting: [PHAsset] = []
        let created = Box<[String: String]>([:]) // original ID -> new still's ID
        let albums = Self.albums(of: originals)
        let budget = Self.copyBudget()
        var planned: Int64 = 0
        do {
            for asset in originals {
                try Task.checkCancellation()
                let size = Self.stillBytes(of: asset)
                if let budget, planned + size > budget { continue }
                planned += size
                stills.append(try await Self.stillFile(of: asset))
                converting.append(asset)
            }
            guard !stills.isEmpty else { throw PhotoChangeError.notEnoughSpace }
            let copies = stills
            let replaced = converting
            try await Self.perform {
                var placeholders: [(originalID: String, placeholder: PHObjectPlaceholder)] = []
                for still in copies {
                    let request = Self.creationRequest(.photo, for: still)
                    if let placeholder = request.placeholderForCreatedAsset {
                        placeholders.append((still.original.localIdentifier, placeholder))
                        created.value[still.original.localIdentifier] = placeholder.localIdentifier
                    }
                }
                Self.add(placeholders, toAlbumsIn: albums)
                // In the same change, so declining iOS's prompt leaves no copies behind.
                PHAssetChangeRequest.deleteAssets(replaced as NSArray)
            }
        } catch {
            stills.forEach { VideoExporter.remove($0.url) }
            throw error
        }

        // Re-read each still and compare it with its original.
        let after = Self.reread(new: Set(created.value.values), originals: Set(converting.map(\.localIdentifier)))
        var results: [StillConversion] = []
        for original in converting {
            guard let stillID = created.value[original.localIdentifier] else { continue }
            let still = after.new[stillID]
            results.append(StillConversion(
                originalID: original.localIdentifier,
                stillID: stillID,
                original: Self.details(of: original, inAlbums: true),
                still: still.map { Self.details(of: $0, inAlbums: Self.isIn(albums[original.localIdentifier], $0)) } ?? Self.missing,
                savedBytes: Self.pairedVideoBytes(of: original)
            ))
        }
        guard results.count == converting.count, after.originalsLeft.isEmpty else {
            throw PhotoChangeError.verificationFailed("Some photos didn't convert. Scan again to see what's there.")
        }
        return results
    }

    func resaveScreenshots(_ approved: Set<MediaItem.ID>) async throws -> ScreenshotResaveReceipt {
        let gate = try await Task.detached(priority: .userInitiated) { try Gate.open(approved) }.value
        let originals = gate.approvedAssets
        let notPNG = originals.filter { !Self.isPNGScreenshot($0) }.count
        guard notPNG == 0 else { throw PhotoChangeError.notResavable(count: notPNG) }

        // Encode every copy to a file before changing anything, so a failed
        // read changes nothing, and keep only the ones that come out clearly smaller.
        var copies: [(copy: Copy, originalBytes: Int64, newBytes: Int64)] = []
        var skipped = Set<String>()
        let created = Box<[String: String]>([:]) // original ID -> copy's ID
        let albums = Self.albums(of: originals)
        do {
            for asset in originals {
                try Task.checkCancellation()
                let originalBytes = Self.bytes(of: asset)
                if let (copy, newBytes) = try await Self.heicFile(of: asset, originalBytes: originalBytes) {
                    copies.append((copy, originalBytes, newBytes))
                } else {
                    skipped.insert(asset.localIdentifier)
                }
            }
            guard !copies.isEmpty else { throw PhotoChangeError.screenshotsNotSmaller }

            let ready = copies.map(\.copy)
            try await Self.perform {
                var placeholders: [(originalID: String, placeholder: PHObjectPlaceholder)] = []
                for copy in ready {
                    let request = Self.creationRequest(.photo, for: copy)
                    if let placeholder = request.placeholderForCreatedAsset {
                        placeholders.append((copy.original.localIdentifier, placeholder))
                        created.value[copy.original.localIdentifier] = placeholder.localIdentifier
                    }
                }
                Self.add(placeholders, toAlbumsIn: albums)
                // In the same change, so declining iOS's prompt leaves no copies behind.
                PHAssetChangeRequest.deleteAssets(ready.map(\.original) as NSArray)
            }
        } catch {
            copies.forEach { VideoExporter.remove($0.copy.url) }
            throw error
        }

        // Re-read each copy and compare it with its original.
        let after = Self.reread(new: Set(created.value.values), originals: Set(copies.map(\.copy.original.localIdentifier)))
        var resaved: [ResavedScreenshot] = []
        for entry in copies {
            let original = entry.copy.original
            guard let newID = created.value[original.localIdentifier] else { continue }
            let new = after.new[newID]
            let newBytes = new.map(Self.bytes(of:)) ?? 0
            resaved.append(ResavedScreenshot(
                originalID: original.localIdentifier,
                newID: newID,
                original: Self.details(of: original, inAlbums: true),
                new: new.map { Self.details(of: $0, inAlbums: Self.isIn(albums[original.localIdentifier], $0)) } ?? Self.missing,
                originalBytes: entry.originalBytes,
                // Photos can take a moment to report a new file's size; the encoded size stands in until then.
                newBytes: newBytes > 0 ? newBytes : entry.newBytes
            ))
        }
        guard resaved.count == copies.count, after.originalsLeft.isEmpty else {
            throw PhotoChangeError.verificationFailed("Some screenshots didn't re-save. Scan again to see what's there.")
        }
        return ScreenshotResaveReceipt(resaved: resaved, skipped: skipped)
    }

    func keepBurstPicks(keep: Set<MediaItem.ID>, remove: Set<MediaItem.ID>) async throws -> BurstReceipt {
        let (gate, plan, before) = try await Task.detached(priority: .userInitiated) {
            guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized else {
                throw PhotoChangeError.needsFullAccess
            }
            let before = PhotoLibrary.burstMembers(with: PhotoLibrary.assets(withIDs: keep))
            // Worked out from the bursts as they are now, and refused unless it matches the review.
            let plan = try BurstPlan.make(keep: keep, expectedRemove: remove, members: before)
            return (try Gate.open(plan.remove), plan, before)
        }.value
        let toDelete = gate.approvedAssets
        let bytes = toDelete.reduce(Int64(0)) { $0 + Self.bytes(of: $1) }

        try await Self.perform {
            PHAssetChangeRequest.deleteAssets(toDelete as NSArray)
        }

        let after = await Task.detached(priority: .userInitiated) {
            PhotoLibrary.burstMembers(with: PhotoLibrary.assets(withIDs: keep))
        }.value
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
        guard let result = try await replaceVideos(with: [prepared]).first else {
            throw PhotoChangeError.verificationFailed(
                "The smaller copy didn't show up in your library. If the original is in Recently Deleted, recover it there."
            )
        }
        return result
    }

    func replaceVideos(with prepared: [PreparedVideo]) async throws -> [VideoReplacement] {
        guard !prepared.isEmpty else { return [] }
        let ids = Set(prepared.map(\.originalID))
        let gate = try await Task.detached(priority: .userInitiated) { try Gate.open(ids) }.value
        let byOriginal = Dictionary(gate.approvedAssets.map { ($0.localIdentifier, $0) }, uniquingKeysWith: { a, _ in a })

        // Every original and copy is checked before anything changes.
        struct Swap {
            let prepared: PreparedVideo
            let original: PHAsset
            let before: VideoDetails
            let name: String
        }
        var swaps: [Swap] = []
        for copy in prepared {
            guard let original = byOriginal[copy.originalID], original.mediaType == .video,
                  Self.version(of: original) == copy.sourceVersion else {
                throw PhotoChangeError.videoUnsupported(
                    prepared.count == 1
                        ? "The video changed since the smaller copy was made. Make it again."
                        : "A video changed since the smaller copies were made. Make them again."
                )
            }
            guard FileManager.default.fileExists(atPath: copy.fileURL.path) else {
                throw PhotoChangeError.videoUnsupported(
                    prepared.count == 1 ? "The smaller copy is gone. Make it again." : "A smaller copy is gone. Make them again."
                )
            }
            let name = PHAssetResource.assetResources(for: original).first { $0.type == .video }?.originalFilename ?? "Video.MOV"
            swaps.append(Swap(prepared: copy, original: original, before: Self.videoDetails(of: original, bytes: copy.originalBytes, inAlbums: true), name: name))
        }

        let albums = Self.albums(of: swaps.map(\.original))
        let created = Box<[String: String]>([:])
        try await Self.perform {
            var placeholders: [(originalID: String, placeholder: PHObjectPlaceholder)] = []
            for swap in swaps {
                let copy = Copy(
                    original: swap.original, url: swap.prepared.fileURL,
                    filename: (swap.name as NSString).deletingPathExtension + ".MOV"
                )
                let request = Self.creationRequest(.video, for: copy)
                if let placeholder = request.placeholderForCreatedAsset {
                    created.value[swap.prepared.originalID] = placeholder.localIdentifier
                    placeholders.append((swap.prepared.originalID, placeholder))
                }
            }
            Self.add(placeholders, toAlbumsIn: albums)
            // In the same change, so declining iOS's prompt leaves no copies behind.
            PHAssetChangeRequest.deleteAssets(swaps.map(\.original) as NSArray)
        }

        // Re-read each copy and compare it with its original.
        let after = Self.reread(new: Set(created.value.values), originals: ids)
        return try swaps.map { swap in
            guard let newID = created.value[swap.prepared.originalID], let copy = after.new[newID] else {
                throw PhotoChangeError.verificationFailed(
                    "A smaller copy didn't show up in your library. If its original is in Recently Deleted, recover it there."
                )
            }
            let copyBytes = Self.bytes(of: copy)
            return VideoReplacement(
                originalID: swap.original.localIdentifier,
                newID: newID,
                edit: swap.prepared.edit,
                original: swap.before,
                // Photos can take a moment to report a new file's size; the measured copy stands in until then.
                new: Self.videoDetails(
                    of: copy, bytes: copyBytes > 0 ? copyBytes : swap.prepared.newBytes,
                    inAlbums: Self.isIn(albums[swap.original.localIdentifier], copy)
                ),
                originalGone: !after.originalsLeft.contains(swap.original.localIdentifier)
            )
        }
    }

    func discard(_ prepared: PreparedVideo) async {
        VideoExporter.remove(prepared.fileURL)
    }

    // MARK: - The gate

    /// Everything a change needs, read fresh, and only if the safety check passed.
    private struct Gate {
        /// The approved assets, each looked up by its own ID.
        let approvedAssets: [PHAsset]
        let check: SafetyCheck

        static func open(_ approved: Set<MediaItem.ID>) throws -> Gate {
            guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized else {
                throw PhotoChangeError.needsFullAccess
            }
            let approvedAssets = PhotoLibrary.assets(withIDs: approved)
            let found = Set(approvedAssets.map(\.localIdentifier))
            let check = SafetyCheck.evaluate(approved: approved, found: found)
            guard check.isSafe else { throw PhotoChangeError.unsafe(check) }
            // Belt and braces: the assets to change are exactly the approved ones.
            guard found == approved, approvedAssets.count == approved.count else {
                throw PhotoChangeError.unsafe(check)
            }
            return Gate(approvedAssets: approvedAssets, check: check)
        }
    }

    // MARK: - Copies

    /// A file in the app's own temporary folder, waiting to replace `original`.
    private struct Copy {
        let original: PHAsset
        let url: URL
        /// The name Photos should give the new item.
        let filename: String
    }

    /// A new item made from `copy`'s file, with the details people care about
    /// taken from its original. Must be called inside a change block.
    private static func creationRequest(_ type: PHAssetResourceType, for copy: Copy) -> PHAssetCreationRequest {
        let request = PHAssetCreationRequest.forAsset()
        let options = PHAssetResourceCreationOptions()
        options.originalFilename = copy.filename
        // Photos takes the file over, so it isn't left in the temporary folder.
        options.shouldMoveFile = true
        request.addResource(with: type, fileURL: copy.url, options: options)
        // EXIF inside the file is kept as is.
        request.creationDate = copy.original.creationDate
        request.location = copy.original.location
        request.isFavorite = copy.original.isFavorite
        request.isHidden = copy.original.isHidden
        return request
    }

    /// For each asset, the albums the person made that hold it.
    private static func albums(of assets: [PHAsset]) -> [String: [PHAssetCollection]] {
        var albums: [String: [PHAssetCollection]] = [:]
        for asset in assets {
            albums[asset.localIdentifier] = PhotoLibrary.userAlbums(containing: asset)
        }
        return albums
    }

    /// Puts each new copy into the albums its original was in. Must be called inside a change block.
    private static func add(
        _ placeholders: [(originalID: String, placeholder: PHObjectPlaceholder)],
        toAlbumsIn albums: [String: [PHAssetCollection]]
    ) {
        var perAlbum: [String: (album: PHAssetCollection, items: [PHObjectPlaceholder])] = [:]
        for entry in placeholders {
            for album in albums[entry.originalID] ?? [] {
                perAlbum[album.localIdentifier, default: (album, [])].items.append(entry.placeholder)
            }
        }
        for entry in perAlbum.values {
            PHAssetCollectionChangeRequest(for: entry.album)?.addAssets(entry.items as NSArray)
        }
    }

    /// True when `copy` is in every one of `albums`, the albums its original was in.
    private static func isIn(_ albums: [PHAssetCollection]?, _ copy: PHAsset) -> Bool {
        guard let albums, !albums.isEmpty else { return true }
        let now = Set(PhotoLibrary.userAlbums(containing: copy).map(\.localIdentifier))
        return now.isSuperset(of: albums.map(\.localIdentifier))
    }

    /// After a swap: the new copies by ID, and which originals are still in the library.
    private static func reread(new: Set<String>, originals: Set<String>) -> (new: [String: PHAsset], originalsLeft: Set<String>) {
        var byID: [String: PHAsset] = [:]
        for asset in PhotoLibrary.assets(withIDs: new) { byID[asset.localIdentifier] = asset }
        return (byID, Set(PhotoLibrary.assets(withIDs: originals).map(\.localIdentifier)))
    }

    private static func copyURL(extension ext: String) throws -> URL {
        try FileManager.default.createDirectory(at: VideoExporter.folder, withIntermediateDirectories: true)
        return VideoExporter.folder.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext.isEmpty ? "jpg" : ext)
    }

    /// A full phone is the likeliest reason a copy can't be written.
    private static func explained(_ error: Error) -> Error {
        let error = error as NSError
        let outOfSpace = (error.domain == NSCocoaErrorDomain && error.code == NSFileWriteOutOfSpaceError)
            || (error.domain == NSPOSIXErrorDomain && error.code == Int(ENOSPC))
        return outOfSpace ? PhotoChangeError.notEnoughSpace : error
    }

    /// How much room new copies may take: half of what's free, so a cleanup
    /// never fills the phone. Nil when free space can't be read.
    private static func copyBudget() -> Int64? {
        let values = try? FileManager.default.temporaryDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage.map { $0 / 2 }
    }

    /// The still image a Live Photo keeps: the edited version if there is one, otherwise the original.
    private static func stillResource(of asset: PHAsset) -> PHAssetResource? {
        let resources = PHAssetResource.assetResources(for: asset)
        return resources.first(where: { $0.type == .fullSizePhoto }) ?? resources.first(where: { $0.type == .photo })
    }

    private static func stillBytes(of asset: PHAsset) -> Int64 {
        stillResource(of: asset).map(PhotoLibrary.fileSize(of:)) ?? 0
    }

    /// The photo exactly as Photos shows it, written to a file: the edited
    /// version if there is one, otherwise the original, with its EXIF untouched.
    private static func stillFile(of asset: PHAsset) async throws -> Copy {
        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = stillResource(of: asset) else {
            throw PhotoChangeError.verificationFailed("A Live Photo had no still image to keep. Nothing was changed.")
        }
        let name = resources.first { $0.type == .photo }?.originalFilename ?? resource.originalFilename
        let url = try copyURL(extension: (resource.originalFilename as NSString).pathExtension)
        let options = PHAssetResourceRequestOptions()
        // Fetches the full photo from iCloud if only a preview is on the phone.
        options.isNetworkAccessAllowed = true
        do {
            try await PHAssetResourceManager.default().writeData(for: resource, toFile: url, options: options)
        } catch {
            VideoExporter.remove(url)
            throw explained(error)
        }
        return Copy(original: asset, url: url, filename: name)
    }

    /// A smaller HEIC copy of a PNG screenshot, written to a file, with its
    /// size. Nil when the copy wouldn't be clearly smaller than the PNG.
    private static func heicFile(of asset: PHAsset, originalBytes: Int64) async throws -> (Copy, Int64)? {
        let source = try await stillImage(of: asset)
        let heic = try heicCopy(of: source.data)
        guard ScreenshotResave.isWorthReplacing(originalBytes: originalBytes, newBytes: Int64(heic.count)) else { return nil }
        let url = try copyURL(extension: "HEIC")
        do {
            try heic.write(to: url)
        } catch {
            VideoExporter.remove(url)
            throw explained(error)
        }
        let name = (source.filename as NSString).deletingPathExtension + ".HEIC"
        return (Copy(original: asset, url: url, filename: name), Int64(heic.count))
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

    /// One photo's data, in memory: the edited version if there is one, otherwise
    /// the original. Only for one image at a time.
    private static func stillImage(of asset: PHAsset) async throws -> (original: PHAsset, data: Data, filename: String) {
        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = resources.first(where: { $0.type == .fullSizePhoto }) ?? resources.first(where: { $0.type == .photo }) else {
            throw PhotoChangeError.verificationFailed("A photo couldn't be read. Nothing was changed.")
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

    private static func details(of asset: PHAsset, inAlbums: Bool) -> AssetDetails {
        AssetDetails(
            creationDate: asset.creationDate,
            latitude: asset.location?.coordinate.latitude,
            longitude: asset.location?.coordinate.longitude,
            isFavorite: asset.isFavorite,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            isLivePhoto: asset.mediaSubtypes.contains(.photoLive),
            inOriginalAlbums: inAlbums
        )
    }

    /// Stands in for a copy that wasn't found in the library afterwards, so every check fails.
    private static let missing = AssetDetails(
        creationDate: nil, latitude: nil, longitude: nil, isFavorite: false,
        pixelWidth: 0, pixelHeight: 0, isLivePhoto: true, inOriginalAlbums: false
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

    private static func videoDetails(of asset: PHAsset, bytes: Int64, inAlbums: Bool) -> VideoDetails {
        VideoDetails(
            creationDate: asset.creationDate,
            latitude: asset.location?.coordinate.latitude,
            longitude: asset.location?.coordinate.longitude,
            isFavorite: asset.isFavorite,
            duration: asset.duration,
            bytes: bytes,
            isVideo: asset.mediaType == .video,
            inOriginalAlbums: inAlbums
        )
    }

    private static func bytes(of asset: PHAsset) -> Int64 {
        PHAssetResource.assetResources(for: asset).reduce(Int64(0)) { $0 + PhotoLibrary.fileSize(of: $1) }
    }

    private static func pairedVideoBytes(of asset: PHAsset) -> Int64 {
        PHAssetResource.assetResources(for: asset)
            .filter { [.pairedVideo, .fullSizePairedVideo, .adjustmentBasePairedVideo].contains($0.type) }
            .reduce(Int64(0)) { $0 + PhotoLibrary.fileSize(of: $1) }
    }
}

/// A mutable box for values filled in from PhotoKit callbacks.
private final class Box<Value>: @unchecked Sendable {
    var value: Value
    init(_ value: Value) { self.value = value }
}
