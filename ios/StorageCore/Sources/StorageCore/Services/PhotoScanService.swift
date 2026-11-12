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

    public var errorDescription: String? {
        switch self {
        case .accessDenied:
            "SimpleShrink can't see your photos. You can allow access in Settings."
        }
    }
}

/// Reads the photo library. Read-only: it never deletes, edits, or adds anything.
public protocol PhotoScanService: Sendable {
    func access() async -> PhotoAccess
    /// Shows the system permission prompt if it hasn't been answered yet.
    func requestAccess() async -> PhotoAccess
    /// Every photo and video the app is allowed to see: the whole library with
    /// full access, or just the picked photos with limited access.
    func scanLibrary() async throws -> [MediaItem]
    /// What the last scan found, kept from an earlier launch, so the app can
    /// show the library straight away while it scans again. Nil when nothing is kept.
    func lastScan() async -> [MediaItem]?
}

public extension PhotoScanService {
    func lastScan() async -> [MediaItem]? { nil }
}

/// Returns fixed items, for tests and previews.
public struct MockPhotoScanService: PhotoScanService {
    public var items: [MediaItem]
    public var grantedAccess: PhotoAccess

    public init(items: [MediaItem], access: PhotoAccess = .granted) {
        self.items = items
        self.grantedAccess = access
    }

    public func access() async -> PhotoAccess { grantedAccess }

    public func requestAccess() async -> PhotoAccess { grantedAccess }

    public func scanLibrary() async throws -> [MediaItem] {
        guard grantedAccess.canRead else { throw PhotoScanError.accessDenied }
        return items
    }
}
