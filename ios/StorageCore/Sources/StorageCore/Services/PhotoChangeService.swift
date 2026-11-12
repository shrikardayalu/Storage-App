import Foundation

public enum PhotoChangeError: LocalizedError, Equatable {
    /// With limited access the app can't see albums, so a copy couldn't be put
    /// back where its original was. Changes need full access.
    case needsFullAccess
    /// The copies need more free space than the phone has right now.
    case notEnoughSpace
    /// The fresh check right before the change failed; nothing was changed.
    case unsafe(SafetyCheck)
    case notLivePhoto(count: Int)
    /// The bursts in the library aren't what the person reviewed.
    case burstsChanged(String)
    /// The duplicates and junk in the library aren't what the person reviewed.
    case junkChanged(String)
    /// The video can't be shrunk, or changed since the copy was made.
    case videoUnsupported(String)
    /// The smaller copy couldn't be made. Nothing in Photos was changed.
    case exportFailed(String)
    /// The copy came out about as big as the original, so it isn't worth swapping.
    case videoNotSmaller
    /// Some items aren't PNG screenshots any more.
    case notResavable(count: Int)
    /// Every screenshot's copy came out about as big as the PNG, so none were swapped.
    case screenshotsNotSmaller
    /// The person tapped Don't Allow on iOS's own confirmation, or iOS refused.
    case cancelled
    /// The change ran, but the library afterwards wasn't what was expected.
    case verificationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .needsFullAccess:
            "SimpleShrink needs full Photos access to make changes. You can allow it in Settings. Nothing was changed."
        case .notEnoughSpace:
            "There isn't enough free space to make the copies. Pick fewer items, or free some space another way first. Nothing was changed."
        case .unsafe(let check):
            "\(check.problem ?? "The safety check failed.") Nothing was changed."
        case .notLivePhoto(let count):
            "\(count == 1 ? "1 item isn't" : "\(count) items aren't") a Live Photo any more. Scan again. Nothing was changed."
        case .burstsChanged(let detail), .junkChanged(let detail):
            "\(detail) Scan again. Nothing was changed."
        case .videoUnsupported(let detail):
            "\(detail) Nothing was changed."
        case .exportFailed(let detail):
            "The smaller copy couldn't be made: \(detail) Nothing was changed."
        case .videoNotSmaller:
            "This video is already about as small as it gets at this quality. Try \u{201C}Smaller file\u{201D} or trimming it. Nothing was changed."
        case .notResavable(let count):
            "\(count == 1 ? "1 item isn't" : "\(count) items aren't") a PNG screenshot any more. Scan again. Nothing was changed."
        case .screenshotsNotSmaller:
            "These screenshots are already about as small as they get. Nothing was changed."
        case .cancelled:
            "Nothing was changed."
        case .verificationFailed(let detail):
            detail
        }
    }
}

/// The only way the app changes the photo library. Every method takes exactly
/// the items the person approved on a review screen, and re-checks, right
/// before changing anything, that every one of them is still in the library.
/// If one item fails, nothing changes. Nothing that wasn't approved is touched.
public protocol PhotoChangeService: Sendable {
    /// Runs the safety check without changing anything, for the review screen.
    func check(_ approved: Set<MediaItem.ID>) async throws -> SafetyCheck
    /// Moves the approved items to Recently Deleted (iOS asks to confirm too),
    /// then confirms that exactly those items left the library.
    func delete(_ approved: Set<MediaItem.ID>) async throws -> DeletionReceipt
    /// Replaces each approved Live Photo with a still of the same photo, keeping
    /// its date, location, favorite and albums. The originals go to Recently Deleted.
    /// On a nearly full phone only as many as there's room for are converted;
    /// the result lists the ones that were, and the rest are left as they are.
    func convertLivePhotosToStills(_ approved: Set<MediaItem.ID>) async throws -> [StillConversion]
    /// Replaces each approved PNG screenshot with a smaller HEIC copy of the same
    /// image, keeping its date, favorite and albums. Screenshots whose copy
    /// wouldn't be much smaller are left alone and listed as skipped; if all
    /// would be, throws `.screenshotsNotSmaller`. The PNGs go to Recently Deleted.
    func resaveScreenshots(_ approved: Set<MediaItem.ID>) async throws -> ScreenshotResaveReceipt
    /// Keeps one picked shot per burst and moves the burst's other shots to
    /// Recently Deleted, then confirms each burst has only its pick left.
    /// `remove` must be exactly the other shots of those bursts, as reviewed.
    func keepBurstPicks(keep: Set<MediaItem.ID>, remove: Set<MediaItem.ID>) async throws -> BurstReceipt
    /// Makes a smaller (and optionally trimmed) copy of one video in the app's
    /// own temporary folder and measures it. Changes nothing in Photos. Throws
    /// `.videoNotSmaller` (and keeps no copy) when it wouldn't save space.
    func prepareVideo(_ id: MediaItem.ID, edit: VideoEdit) async throws -> PreparedVideo
    /// Replaces the original video with its prepared copy, keeping its date,
    /// location, favorite and albums. The original goes to Recently Deleted in
    /// the same change. Afterwards the copy is re-read and checked.
    func replaceVideo(with prepared: PreparedVideo) async throws -> VideoReplacement
    /// Replaces several videos with their prepared copies in one change, so iOS
    /// asks once. Same checks and guarantees as `replaceVideo`; if any original
    /// changed or any copy is missing, nothing changes.
    func replaceVideos(with prepared: [PreparedVideo]) async throws -> [VideoReplacement]
    /// Throws away a prepared copy that won't be used.
    func discard(_ prepared: PreparedVideo) async
}
