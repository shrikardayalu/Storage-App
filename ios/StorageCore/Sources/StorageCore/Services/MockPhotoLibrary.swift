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
}
