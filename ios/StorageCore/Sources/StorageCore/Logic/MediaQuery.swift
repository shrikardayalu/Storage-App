import Foundation

/// Which items the Library tab shows.
public enum MediaFilter: String, CaseIterable, Hashable, Sendable, Identifiable {
    case all
    case photos
    case videos
    case screenshots
    case largeVideos

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: "All"
        case .photos: "Photos"
        case .videos: "Videos"
        case .screenshots: "Screenshots"
        case .largeVideos: "Large Videos"
        }
    }

    public func includes(_ item: MediaItem) -> Bool {
        switch self {
        case .all: true
        case .photos: item.category == .photo
        case .videos: item.category == .video
        case .screenshots: item.category == .screenshot
        case .largeVideos: item.category == .video && item.currentBytes >= LibrarySummary.largeVideoThreshold
        }
    }
}

/// Library sort orders.
public enum MediaSort: String, CaseIterable, Hashable, Sendable, Identifiable {
    case largestFirst
    case smallestFirst
    case newestFirst
    case oldestFirst

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .largestFirst: "Largest First"
        case .smallestFirst: "Smallest First"
        case .newestFirst: "Newest First"
        case .oldestFirst: "Oldest First"
        }
    }

    /// Strict ordering with the item ID as a tie-breaker, so equal sizes or
    /// dates never reorder between refreshes.
    public func areInIncreasingOrder(_ a: MediaItem, _ b: MediaItem) -> Bool {
        switch self {
        case .largestFirst:
            a.currentBytes != b.currentBytes ? a.currentBytes > b.currentBytes : a.id < b.id
        case .smallestFirst:
            a.currentBytes != b.currentBytes ? a.currentBytes < b.currentBytes : a.id < b.id
        case .newestFirst:
            a.creationDate != b.creationDate ? a.creationDate > b.creationDate : a.id < b.id
        case .oldestFirst:
            a.creationDate != b.creationDate ? a.creationDate < b.creationDate : a.id < b.id
        }
    }
}

public enum MediaQuery {
    public static func apply(filter: MediaFilter, sort: MediaSort, to items: [MediaItem]) -> [MediaItem] {
        items.filter(filter.includes).sorted(by: sort.areInIncreasingOrder)
    }
}
