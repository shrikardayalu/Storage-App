import Foundation

/// The set of item IDs the user has picked for cleanup.
public struct MediaSelection: Hashable, Sendable {
    public private(set) var ids: Set<MediaItem.ID> = []

    public init(ids: Set<MediaItem.ID> = []) {
        self.ids = ids
    }

    public var count: Int { ids.count }
    public var isEmpty: Bool { ids.isEmpty }

    public func contains(_ id: MediaItem.ID) -> Bool { ids.contains(id) }

    public mutating func toggle(_ id: MediaItem.ID) {
        if ids.remove(id) == nil { ids.insert(id) }
    }

    public mutating func select<S: Sequence>(_ newIDs: S) where S.Element == MediaItem.ID {
        ids.formUnion(newIDs)
    }

    public mutating func deselect<S: Sequence>(_ removed: S) where S.Element == MediaItem.ID {
        ids.subtract(removed)
    }

    public mutating func clear() { ids.removeAll() }

    /// True when every one of `candidates` is selected (and there is at least one).
    public func containsAll(_ candidates: [MediaItem]) -> Bool {
        !candidates.isEmpty && candidates.allSatisfy { ids.contains($0.id) }
    }

    /// Drops IDs that no longer exist in the library (after a deletion or reset).
    public mutating func prune(keeping existing: Set<MediaItem.ID>) {
        ids.formIntersection(existing)
    }
}
