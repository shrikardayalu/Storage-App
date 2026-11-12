import Foundation

/// The result of checking a set of approved items against the photo library,
/// right before anything is changed. Changes go ahead only when `isSafe`.
///
/// An item passes only if it is still in the library, as the person saw it
/// on the review screen. A change only ever reaches the approved items.
public struct SafetyCheck: Hashable, Sendable {
    /// What the person approved.
    public let approved: Set<MediaItem.ID>
    /// Approved items that are no longer in the library.
    public let missing: Set<MediaItem.ID>

    public init(approved: Set<MediaItem.ID>, missing: Set<MediaItem.ID> = []) {
        self.approved = approved
        self.missing = missing
    }

    /// Checks `approved` against what the library holds right now.
    /// - Parameter found: the approved IDs that were found in the library, fetched fresh.
    public static func evaluate(approved: Set<MediaItem.ID>, found: Set<MediaItem.ID>) -> SafetyCheck {
        SafetyCheck(approved: approved, missing: approved.subtracting(found))
    }

    /// Items that pass the check.
    public var verified: Set<MediaItem.ID> {
        approved.subtracting(missing)
    }

    /// True only when there is something approved and every approved item passes.
    /// One failing item blocks the whole change; nothing is skipped quietly.
    public var isSafe: Bool {
        !approved.isEmpty && missing.isEmpty
    }

    /// Why the change was blocked, in plain words; nil when safe.
    public var problem: String? {
        if approved.isEmpty { return "Nothing was approved." }
        if !missing.isEmpty {
            return "\(Self.count(missing.count)) no longer in your library. Scan again, then review."
        }
        return nil
    }

    private static func count(_ n: Int) -> String {
        n == 1 ? "1 item is" : "\(n) items are"
    }
}

/// Proof of what a deletion did: the library before and after, and whether
/// exactly the approved items, and nothing else, left it.
public struct DeletionReceipt: Hashable, Sendable {
    public let deleted: Set<MediaItem.ID>
    public let countBefore: Int
    public let countAfter: Int
    public let deletedBytes: Int64
    /// True when every approved item left the library and nothing else did.
    public let onlyApprovedRemoved: Bool

    public init(deleted: Set<MediaItem.ID>, countBefore: Int, countAfter: Int, deletedBytes: Int64, onlyApprovedRemoved: Bool) {
        self.deleted = deleted
        self.countBefore = countBefore
        self.countAfter = countAfter
        self.deletedBytes = deletedBytes
        self.onlyApprovedRemoved = onlyApprovedRemoved
    }

    /// Compares the library's members before and after a deletion. Items
    /// added meanwhile (a new photo, an iCloud sync) don't count against it.
    public static func audit(
        approved: Set<MediaItem.ID>,
        before: Set<MediaItem.ID>,
        after: Set<MediaItem.ID>,
        deletedBytes: Int64
    ) -> DeletionReceipt {
        DeletionReceipt(
            deleted: before.subtracting(after),
            countBefore: before.count,
            countAfter: after.count,
            deletedBytes: deletedBytes,
            onlyApprovedRemoved: before.subtracting(after) == approved
        )
    }

    /// The same audit without listing a whole library: which approved items
    /// are still there, and how many items the library held before and after.
    /// It passes only when every approved item is gone and the library shrank
    /// by no more than that, so nothing else can have left with them.
    public static func audit(
        approved: Set<MediaItem.ID>,
        stillPresent: Set<MediaItem.ID>,
        countBefore: Int,
        countAfter: Int,
        deletedBytes: Int64
    ) -> DeletionReceipt {
        DeletionReceipt(
            deleted: approved.subtracting(stillPresent),
            countBefore: countBefore,
            countAfter: countAfter,
            deletedBytes: deletedBytes,
            onlyApprovedRemoved: stillPresent.isDisjoint(with: approved) && countAfter >= countBefore - approved.count
        )
    }
}

/// The details of a photo that a Live Photo → still conversion must keep.
/// `inOriginalAlbums` is true when it's in every album its original was in.
public struct AssetDetails: Hashable, Sendable {
    public var creationDate: Date?
    public var latitude: Double?
    public var longitude: Double?
    public var isFavorite: Bool
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var isLivePhoto: Bool
    public var inOriginalAlbums: Bool

    public init(
        creationDate: Date?,
        latitude: Double?,
        longitude: Double?,
        isFavorite: Bool,
        pixelWidth: Int,
        pixelHeight: Int,
        isLivePhoto: Bool,
        inOriginalAlbums: Bool
    ) {
        self.creationDate = creationDate
        self.latitude = latitude
        self.longitude = longitude
        self.isFavorite = isFavorite
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.isLivePhoto = isLivePhoto
        self.inOriginalAlbums = inOriginalAlbums
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
        keptAlbum = still.inOriginalAlbums
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
