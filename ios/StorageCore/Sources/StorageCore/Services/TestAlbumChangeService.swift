import Foundation

public enum PhotoChangeError: LocalizedError, Equatable {
    /// Limited access hides albums, so album membership can't be confirmed.
    case needsFullAccess
    case albumNotFound(String)
    /// More than one album has the test album's name, so which one is meant is unclear.
    case albumAmbiguous(String)
    /// The fresh check right before the change failed; nothing was changed.
    case unsafe(SafetyCheck)
    case notLivePhoto(count: Int)
    /// The person tapped Don't Allow on iOS's own confirmation, or iOS refused.
    case cancelled
    /// The change ran, but the album afterwards wasn't what was expected.
    case verificationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .needsFullAccess:
            "Storage App needs full Photos access to check that each item is in \u{201C}\(TestMode.albumName)\u{201D} before changing it. Nothing was changed."
        case .albumNotFound(let name):
            "There's no album named \u{201C}\(name)\u{201D}. Nothing was changed."
        case .albumAmbiguous(let name):
            "More than one album is named \u{201C}\(name)\u{201D}. Rename the extras so Storage App knows which one to use. Nothing was changed."
        case .unsafe(let check):
            "\(check.problem ?? "The safety check failed.") Nothing was changed."
        case .notLivePhoto(let count):
            "\(count == 1 ? "1 item isn't" : "\(count) items aren't") a Live Photo any more. Scan again. Nothing was changed."
        case .cancelled:
            "Nothing was changed."
        case .verificationFailed(let detail):
            detail
        }
    }
}

/// The only way the app changes the photo library. Every method works on the
/// "Storage App Test" album and nothing else: the album isn't a parameter, and
/// each call re-checks, right before changing anything, that every approved
/// item is in that album and in no other. If one item fails, nothing changes.
public protocol TestAlbumChangeService: Sendable {
    /// Runs the safety check without changing anything, for the review screen.
    func check(_ approved: Set<MediaItem.ID>) async throws -> SafetyCheck
    /// Moves the approved items to Recently Deleted (iOS asks to confirm too),
    /// then confirms that exactly those items left the album.
    func delete(_ approved: Set<MediaItem.ID>) async throws -> DeletionReceipt
    /// Replaces each approved Live Photo with a still of the same photo, keeping
    /// its date, location, favorite and album. The originals go to Recently Deleted.
    func convertLivePhotosToStills(_ approved: Set<MediaItem.ID>) async throws -> [StillConversion]
}
