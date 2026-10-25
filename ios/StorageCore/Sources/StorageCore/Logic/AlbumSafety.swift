import Foundation

/// The result of checking a set of approved items against the test album,
/// right before anything is changed. Changes go ahead only when `isSafe`.
///
/// An item passes only if it is in the "Storage App Test" album and in no
/// other album the person made, so a change can never reach a photo that
/// belongs anywhere else.
public struct SafetyCheck: Hashable, Sendable {
    /// What the person approved.
    public let approved: Set<MediaItem.ID>
    /// Approved items that are no longer (or never were) in the test album.
    public let outsideTestAlbum: Set<MediaItem.ID>
    /// Approved items that are also in another album the person made.
    public let inOtherAlbums: Set<MediaItem.ID>

    public init(approved: Set<MediaItem.ID>, outsideTestAlbum: Set<MediaItem.ID>, inOtherAlbums: Set<MediaItem.ID>) {
        self.approved = approved
        self.outsideTestAlbum = outsideTestAlbum
        self.inOtherAlbums = inOtherAlbums
    }

    /// Checks `approved` against what the album holds right now.
    /// - Parameters:
    ///   - testAlbumMembers: every item ID in the test album, fetched fresh.
    ///   - otherAlbumMembers: approved IDs that some other user album also holds.
    public static func evaluate(
        approved: Set<MediaItem.ID>,
        testAlbumMembers: Set<MediaItem.ID>,
        otherAlbumMembers: Set<MediaItem.ID>
    ) -> SafetyCheck {
        SafetyCheck(
            approved: approved,
            outsideTestAlbum: approved.subtracting(testAlbumMembers),
            inOtherAlbums: approved.intersection(otherAlbumMembers)
        )
    }

    /// Items that pass every check.
    public var verified: Set<MediaItem.ID> {
        approved.subtracting(outsideTestAlbum).subtracting(inOtherAlbums)
    }

    /// True only when there is something approved and every approved item passes.
    /// One failing item blocks the whole change; nothing is skipped quietly.
    public var isSafe: Bool {
        !approved.isEmpty && outsideTestAlbum.isEmpty && inOtherAlbums.isEmpty
    }

    /// Why the change was blocked, in plain words; nil when safe.
    public var problem: String? {
        if approved.isEmpty { return "Nothing was approved." }
        if !outsideTestAlbum.isEmpty {
            return "\(Self.count(outsideTestAlbum.count)) no longer in \u{201C}\(TestMode.albumName)\u{201D}. Scan again, then review."
        }
        if !inOtherAlbums.isEmpty {
            return "\(Self.count(inOtherAlbums.count)) also in another album, so Storage App won't touch \(inOtherAlbums.count == 1 ? "it" : "them"). Remove \(inOtherAlbums.count == 1 ? "it" : "them") from this review."
        }
        return nil
    }

    private static func count(_ n: Int) -> String {
        n == 1 ? "1 item is" : "\(n) items are"
    }
}

/// Proof of what a deletion did: the album before and after, and whether
/// exactly the approved items, and nothing else, left it.
public struct DeletionReceipt: Hashable, Sendable {
    public let deleted: Set<MediaItem.ID>
    public let albumCountBefore: Int
    public let albumCountAfter: Int
    public let deletedBytes: Int64
    /// True when the album after equals the album before minus the approved items.
    public let onlyApprovedRemoved: Bool

    public init(deleted: Set<MediaItem.ID>, albumCountBefore: Int, albumCountAfter: Int, deletedBytes: Int64, onlyApprovedRemoved: Bool) {
        self.deleted = deleted
        self.albumCountBefore = albumCountBefore
        self.albumCountAfter = albumCountAfter
        self.deletedBytes = deletedBytes
        self.onlyApprovedRemoved = onlyApprovedRemoved
    }

    /// Compares the album's members before and after a deletion.
    public static func audit(
        approved: Set<MediaItem.ID>,
        before: Set<MediaItem.ID>,
        after: Set<MediaItem.ID>,
        deletedBytes: Int64
    ) -> DeletionReceipt {
        DeletionReceipt(
            deleted: before.subtracting(after),
            albumCountBefore: before.count,
            albumCountAfter: after.count,
            deletedBytes: deletedBytes,
            onlyApprovedRemoved: after == before.subtracting(approved)
        )
    }
}

/// The details of a photo that a Live Photo → still conversion must keep.
public struct AssetDetails: Hashable, Sendable {
    public var creationDate: Date?
    public var latitude: Double?
    public var longitude: Double?
    public var isFavorite: Bool
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var isLivePhoto: Bool
    public var inTestAlbum: Bool

    public init(
        creationDate: Date?,
        latitude: Double?,
        longitude: Double?,
        isFavorite: Bool,
        pixelWidth: Int,
        pixelHeight: Int,
        isLivePhoto: Bool,
        inTestAlbum: Bool
    ) {
        self.creationDate = creationDate
        self.latitude = latitude
        self.longitude = longitude
        self.isFavorite = isFavorite
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.isLivePhoto = isLivePhoto
        self.inTestAlbum = inTestAlbum
    }
}

/// One Live Photo replaced by a still, with what was checked afterwards.
public struct StillConversion: Hashable, Sendable, Identifiable {
    public let originalID: MediaItem.ID
    public let stillID: MediaItem.ID
    public let keptDate: Bool
    public let keptLocation: Bool
    public let keptFavorite: Bool
    public let keptAlbum: Bool
    /// Same pixel size, and no longer a Live Photo.
    public let isSameStill: Bool
    /// The paired video's size, which emptying Recently Deleted gets back.
    public let savedBytes: Int64

    public var id: MediaItem.ID { originalID }

    public var keptEverything: Bool {
        keptDate && keptLocation && keptFavorite && keptAlbum && isSameStill
    }

    public init(originalID: MediaItem.ID, stillID: MediaItem.ID, original: AssetDetails, still: AssetDetails, savedBytes: Int64) {
        self.originalID = originalID
        self.stillID = stillID
        self.savedBytes = savedBytes
        // Photos stores dates to the millisecond; allow for rounding.
        if let a = original.creationDate, let b = still.creationDate {
            keptDate = abs(a.timeIntervalSince(b)) < 1
        } else {
            keptDate = original.creationDate == nil && still.creationDate == nil
        }
        keptLocation = Self.same(original.latitude, still.latitude) && Self.same(original.longitude, still.longitude)
        keptFavorite = original.isFavorite == still.isFavorite
        keptAlbum = still.inTestAlbum
        isSameStill = !still.isLivePhoto
            && original.pixelWidth == still.pixelWidth
            && original.pixelHeight == still.pixelHeight
    }

    private static func same(_ a: Double?, _ b: Double?) -> Bool {
        switch (a, b) {
        case (nil, nil): true
        case let (a?, b?): abs(a - b) < 0.000_01
        default: false
        }
    }
}
