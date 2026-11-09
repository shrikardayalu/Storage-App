import Foundation

/// Whether the app may read the photo library.
public enum PhotoAccess: Sendable, Equatable {
    case notDetermined
    case granted
    /// The person picked specific photos; a scan sees only those.
    case limited
    case denied

    public var canRead: Bool { self == .granted || self == .limited }
}

public enum PhotoScanError: LocalizedError, Equatable {
    case accessDenied
    case albumNotFound(String)
    case albumAmbiguous(String)

    public var errorDescription: String? {
        switch self {
        case .accessDenied:
            "SimpleShrink can't see your photos. You can allow access in Settings."
        case .albumNotFound(let name):
            "There's no album named \"\(name)\". Make one in the Photos app, then scan again."
        case .albumAmbiguous(let name):
            "More than one album is named \"\(name)\". Rename the extras, then scan again."
        }
    }
}

/// Reads media from one album of the photo library. Read-only: it never
/// deletes, edits, or adds anything.
public protocol PhotoScanService: Sendable {
    func access() async -> PhotoAccess
    /// Shows the system permission prompt if it hasn't been answered yet.
    func requestAccess() async -> PhotoAccess
    /// Every item in the album named `albumName`.
    func scanAlbum(named albumName: String) async throws -> [MediaItem]
}

/// Test Mode: until launch, the app reads only this one album, so it sees
/// nothing else in the library.
public enum TestMode {
    public static let albumName = "Storage App Test"
}

/// Returns fixed items, for tests and previews.
public struct MockPhotoScanService: PhotoScanService {
    public var items: [MediaItem]
    public var grantedAccess: PhotoAccess
    public var albumExists: Bool

    public init(items: [MediaItem], access: PhotoAccess = .granted, albumExists: Bool = true) {
        self.items = items
        self.grantedAccess = access
        self.albumExists = albumExists
    }

    public func access() async -> PhotoAccess { grantedAccess }

    public func requestAccess() async -> PhotoAccess { grantedAccess }

    public func scanAlbum(named albumName: String) async throws -> [MediaItem] {
        guard grantedAccess.canRead else { throw PhotoScanError.accessDenied }
        guard albumExists else { throw PhotoScanError.albumNotFound(albumName) }
        return items
    }
}
