import Foundation

/// Re-saving screenshots: iPhone saves screenshots as PNG, a lossless format
/// built for perfect copies rather than small files. The same image saved as
/// high-quality HEIC looks the same on the phone and is usually 60-80% smaller.
/// The new copy keeps the screenshot's date, favorite and album; the PNG goes
/// to Recently Deleted.
public enum ScreenshotResave {
    /// HEIC quality used for the copy. High enough that text stays crisp.
    public static let quality = 0.9
    /// How big the copy usually comes out, as a share of the PNG. On the
    /// cautious side, so estimates never overpromise.
    public static let estimatedRatio = 0.35
    /// The copy must be at least this much smaller, or the PNG is left alone:
    /// re-encoding isn't worth it for a small saving.
    public static let minimumSaving = 0.2

    /// A screenshot still saved as PNG. Anything else is already compressed.
    public static func isResavable(_ item: MediaItem) -> Bool {
        item.category == .screenshot && item.format == .png && item.burstID == nil
    }

    /// What re-saving this screenshot should save, before it's been tried.
    public static func estimatedSaving(for item: MediaItem) -> Int64 {
        guard isResavable(item) else { return 0 }
        return Int64((Double(item.currentBytes) * (1 - estimatedRatio)).rounded(.down))
    }

    /// The copy's size, estimated the same way.
    public static func estimatedBytes(for item: MediaItem) -> Int64 {
        item.currentBytes - estimatedSaving(for: item)
    }

    public static func isWorthReplacing(originalBytes: Int64, newBytes: Int64) -> Bool {
        newBytes > 0 && originalBytes > 0 && Double(newBytes) <= Double(originalBytes) * (1 - minimumSaving)
    }
}

/// One screenshot replaced by a smaller copy, with what was checked afterwards.
public struct ResavedScreenshot: Hashable, Sendable, Identifiable {
    public let originalID: MediaItem.ID
    public let newID: MediaItem.ID
    public let originalBytes: Int64
    public let newBytes: Int64
    public let keptDate: Bool
    public let keptFavorite: Bool
    public let keptAlbum: Bool
    /// Same pixel size as the original.
    public let isSameSize: Bool

    public var id: MediaItem.ID { originalID }

    /// What emptying Recently Deleted gets back: the PNG, less the copy that replaced it.
    public var savedBytes: Int64 { max(0, originalBytes - newBytes) }

    public var keptEverything: Bool { keptDate && keptFavorite && keptAlbum && isSameSize }

    public init(originalID: MediaItem.ID, newID: MediaItem.ID, original: AssetDetails, new: AssetDetails,
                originalBytes: Int64, newBytes: Int64) {
        self.originalID = originalID
        self.newID = newID
        self.originalBytes = originalBytes
        self.newBytes = newBytes
        // Photos stores dates to the millisecond; allow for rounding.
        if let a = original.creationDate, let b = new.creationDate {
            keptDate = abs(a.timeIntervalSince(b)) < 1
        } else {
            keptDate = original.creationDate == nil && new.creationDate == nil
        }
        keptFavorite = original.isFavorite == new.isFavorite
        keptAlbum = new.inTestAlbum
        isSameSize = original.pixelWidth == new.pixelWidth && original.pixelHeight == new.pixelHeight
    }
}

/// What a re-save did: the screenshots replaced, and the ones left alone
/// because their copy wouldn't have been much smaller.
public struct ScreenshotResaveReceipt: Hashable, Sendable {
    public let resaved: [ResavedScreenshot]
    public let skipped: Set<MediaItem.ID>

    public init(resaved: [ResavedScreenshot], skipped: Set<MediaItem.ID>) {
        self.resaved = resaved
        self.skipped = skipped
    }

    public var savedBytes: Int64 { resaved.reduce(0) { $0 + $1.savedBytes } }
}
