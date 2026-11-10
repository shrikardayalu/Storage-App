import Foundation

/// An in-memory test album that both scans and changes, for tests and previews.
/// It follows the same rules as the real PhotoKit service: every change is
/// checked against the album first, and one failing item blocks the whole change.
public actor MockPhotoLibrary: PhotoScanService, TestAlbumChangeService {
    public private(set) var items: [MediaItem]
    /// Item IDs that some other user album also holds.
    public private(set) var inOtherAlbums: Set<MediaItem.ID>
    /// Items outside the test album: the rest of the library. Nothing may change them.
    public private(set) var outsideItems: [MediaItem]
    public var grantedAccess: PhotoAccess
    /// When true, the change acts like the person tapping Don't Allow on iOS's prompt.
    public var declinesChanges = false
    /// How many times something in the library was changed.
    public private(set) var changeCount = 0
    /// Copies made by `prepareVideo` and not yet used or discarded.
    public private(set) var preparedVideos: Set<UUID> = []

    public init(
        items: [MediaItem],
        inOtherAlbums: Set<MediaItem.ID> = [],
        outsideItems: [MediaItem] = [],
        access: PhotoAccess = .granted
    ) {
        self.items = items
        self.inOtherAlbums = inOtherAlbums
        self.outsideItems = outsideItems
        self.grantedAccess = access
    }

    public func setDeclinesChanges(_ value: Bool) {
        declinesChanges = value
    }

    // MARK: PhotoScanService

    public func access() async -> PhotoAccess { grantedAccess }

    public func requestAccess() async -> PhotoAccess { grantedAccess }

    public func scanAlbum(named albumName: String) async throws -> [MediaItem] {
        guard grantedAccess.canRead else { throw PhotoScanError.accessDenied }
        return items
    }

    // MARK: TestAlbumChangeService

    public func check(_ approved: Set<MediaItem.ID>) async throws -> SafetyCheck {
        guard grantedAccess == .granted else { throw PhotoChangeError.needsFullAccess }
        return SafetyCheck.evaluate(
            approved: approved,
            testAlbumMembers: Set(items.map(\.id)),
            otherAlbumMembers: inOtherAlbums
        )
    }

    public func delete(_ approved: Set<MediaItem.ID>) async throws -> DeletionReceipt {
        let check = try await check(approved)
        guard check.isSafe else { throw PhotoChangeError.unsafe(check) }
        guard !declinesChanges else { throw PhotoChangeError.cancelled }

        let before = Set(items.map(\.id))
        let bytes = items.filter { approved.contains($0.id) }.reduce(0) { $0 + $1.currentBytes }
        items.removeAll { approved.contains($0.id) }
        changeCount += 1
        return DeletionReceipt.audit(approved: approved, before: before, after: Set(items.map(\.id)), deletedBytes: bytes)
    }

    public func convertLivePhotosToStills(_ approved: Set<MediaItem.ID>) async throws -> [StillConversion] {
        let check = try await check(approved)
        guard check.isSafe else { throw PhotoChangeError.unsafe(check) }
        let originals = items.filter { approved.contains($0.id) }
        let notLive = originals.filter { !$0.isConvertibleLivePhoto }.count
        guard notLive == 0 else { throw PhotoChangeError.notLivePhoto(count: notLive) }
        guard !declinesChanges else { throw PhotoChangeError.cancelled }

        var results: [StillConversion] = []
        for original in originals {
            let still = MediaItem(
                id: "\(original.id)-still",
                category: .photo,
                format: original.format,
                filename: original.filename,
                creationDate: original.creationDate,
                pixelWidth: original.pixelWidth,
                pixelHeight: original.pixelHeight,
                duration: nil,
                originalBytes: original.originalBytes - original.livePhotoVideoBytes,
                thumbnailSeed: original.thumbnailSeed
            )
            items.removeAll { $0.id == original.id }
            items.append(still)
            let details = AssetDetails(
                creationDate: original.creationDate, latitude: nil, longitude: nil, isFavorite: false,
                pixelWidth: original.pixelWidth, pixelHeight: original.pixelHeight, isLivePhoto: true, inTestAlbum: true
            )
            var stillDetails = details
            stillDetails.isLivePhoto = false
            results.append(StillConversion(
                originalID: original.id, stillID: still.id, original: details, still: stillDetails,
                savedBytes: original.livePhotoVideoBytes
            ))
        }
        changeCount += 1
        return results
    }

    public func resaveScreenshots(_ approved: Set<MediaItem.ID>) async throws -> ScreenshotResaveReceipt {
        let check = try await check(approved)
        guard check.isSafe else { throw PhotoChangeError.unsafe(check) }
        let originals = items.filter { approved.contains($0.id) }
        let notPNG = originals.filter { !ScreenshotResave.isResavable($0) }.count
        guard notPNG == 0 else { throw PhotoChangeError.notResavable(count: notPNG) }

        let worth = originals.filter {
            ScreenshotResave.isWorthReplacing(originalBytes: $0.currentBytes, newBytes: ScreenshotResave.estimatedBytes(for: $0))
        }
        guard !worth.isEmpty else { throw PhotoChangeError.screenshotsNotSmaller }
        guard !declinesChanges else { throw PhotoChangeError.cancelled }

        var resaved: [ResavedScreenshot] = []
        for original in worth {
            let newBytes = ScreenshotResave.estimatedBytes(for: original)
            let copy = MediaItem(
                id: "\(original.id)-heic", category: .screenshot, format: .heic,
                filename: (original.filename as NSString).deletingPathExtension + ".HEIC",
                creationDate: original.creationDate, pixelWidth: original.pixelWidth, pixelHeight: original.pixelHeight,
                duration: nil, originalBytes: newBytes, thumbnailSeed: original.thumbnailSeed
            )
            items.removeAll { $0.id == original.id }
            items.append(copy)
            let details = AssetDetails(
                creationDate: original.creationDate, latitude: nil, longitude: nil, isFavorite: false,
                pixelWidth: original.pixelWidth, pixelHeight: original.pixelHeight, isLivePhoto: false, inTestAlbum: true
            )
            resaved.append(ResavedScreenshot(
                originalID: original.id, newID: copy.id, original: details, new: details,
                originalBytes: original.currentBytes, newBytes: newBytes
            ))
        }
        changeCount += 1
        return ScreenshotResaveReceipt(resaved: resaved, skipped: Set(originals.map(\.id)).subtracting(worth.map(\.id)))
    }

    public func keepBurstPicks(keep: Set<MediaItem.ID>, remove: Set<MediaItem.ID>) async throws -> BurstReceipt {
        let before = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.burstID) })
        let plan = try BurstPlan.make(keep: keep, expectedRemove: remove, members: before)
        let check = try await check(plan.remove)
        guard check.isSafe else { throw PhotoChangeError.unsafe(check) }
        guard !declinesChanges else { throw PhotoChangeError.cancelled }

        let bytes = items.filter { plan.remove.contains($0.id) }.reduce(0) { $0 + $1.currentBytes }
        items.removeAll { plan.remove.contains($0.id) }
        changeCount += 1
        let after = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.burstID) })
        return BurstReceipt.audit(plan: plan, before: before, after: after, removedBytes: bytes)
    }

    public func prepareVideo(_ id: MediaItem.ID, edit: VideoEdit) async throws -> PreparedVideo {
        let check = try await check([id])
        guard check.isSafe else { throw PhotoChangeError.unsafe(check) }
        guard let item = items.first(where: { $0.id == id }) else { throw PhotoChangeError.unsafe(check) }
        if let reason = VideoShrink.unsupportedReason(for: item) { throw PhotoChangeError.videoUnsupported(reason) }
        let duration = item.duration ?? 0
        let newBytes = VideoShrink.estimatedBytes(for: item, edit: edit)
        guard VideoShrink.isWorthReplacing(originalBytes: item.currentBytes, newBytes: newBytes) else {
            throw PhotoChangeError.videoNotSmaller
        }
        let prepared = PreparedVideo(
            originalID: id, edit: edit, fileURL: URL(fileURLWithPath: "/mock/\(id).mov"),
            originalBytes: item.currentBytes, newBytes: newBytes,
            newDuration: edit.trim.clamped(to: duration).length, sourceVersion: "\(item.currentBytes)"
        )
        preparedVideos.insert(prepared.id)
        return prepared
    }

    public func replaceVideo(with prepared: PreparedVideo) async throws -> VideoReplacement {
        guard preparedVideos.contains(prepared.id) else {
            throw PhotoChangeError.videoUnsupported("That smaller copy is gone. Make it again.")
        }
        let check = try await check([prepared.originalID])
        guard check.isSafe else { throw PhotoChangeError.unsafe(check) }
        guard let original = items.first(where: { $0.id == prepared.originalID }),
              "\(original.currentBytes)" == prepared.sourceVersion else {
            throw PhotoChangeError.videoUnsupported("The video changed since the copy was made.")
        }
        guard !declinesChanges else { throw PhotoChangeError.cancelled }

        let out = VideoShrink.outputSize(width: original.pixelWidth, height: original.pixelHeight, quality: prepared.edit.quality)
        let copy = MediaItem(
            id: "\(original.id)-small", category: .video, format: .hevc, filename: original.filename,
            creationDate: original.creationDate, pixelWidth: out.width, pixelHeight: out.height,
            duration: prepared.newDuration, originalBytes: prepared.newBytes, thumbnailSeed: original.thumbnailSeed
        )
        items.removeAll { $0.id == original.id }
        items.append(copy)
        preparedVideos.remove(prepared.id)
        changeCount += 1

        func details(_ item: MediaItem) -> VideoDetails {
            VideoDetails(creationDate: item.creationDate, latitude: nil, longitude: nil, isFavorite: false,
                         duration: item.duration ?? 0, bytes: item.currentBytes, isVideo: true, inTestAlbum: true)
        }
        return VideoReplacement(
            originalID: original.id, newID: copy.id, edit: prepared.edit,
            original: details(original), new: details(copy), originalGone: true
        )
    }

    public func replaceVideos(with prepared: [PreparedVideo]) async throws -> [VideoReplacement] {
        // Checks every copy first, so a bad one leaves everything as it was.
        for copy in prepared {
            guard preparedVideos.contains(copy.id) else {
                throw PhotoChangeError.videoUnsupported("That smaller copy is gone. Make it again.")
            }
            guard let original = items.first(where: { $0.id == copy.originalID }),
                  "\(original.currentBytes)" == copy.sourceVersion else {
                throw PhotoChangeError.videoUnsupported("A video changed since the copies were made.")
            }
        }
        let check = try await check(Set(prepared.map(\.originalID)))
        guard check.isSafe else { throw PhotoChangeError.unsafe(check) }
        guard !declinesChanges else { throw PhotoChangeError.cancelled }
        let changesBefore = changeCount
        var results: [VideoReplacement] = []
        for copy in prepared {
            results.append(try await replaceVideo(with: copy))
        }
        changeCount = changesBefore + 1
        return results
    }

    public func discard(_ prepared: PreparedVideo) async {
        preparedVideos.remove(prepared.id)
    }
}
