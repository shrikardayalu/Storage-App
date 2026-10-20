import Foundation

/// What a cleanup action did, for the result screen and the undo banner.
public struct CleanupResult: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case deletion
        case compression(CompressionLevel)
    }

    public let kind: Kind
    public let itemCount: Int
    public let bytesRecovered: Int64
    /// Items left untouched because the action didn't apply to them.
    public let skippedCount: Int

    public init(kind: Kind, itemCount: Int, bytesRecovered: Int64, skippedCount: Int = 0) {
        self.kind = kind
        self.itemCount = itemCount
        self.bytesRecovered = bytesRecovered
        self.skippedCount = skippedCount
    }
}

public enum MediaLibraryError: Error, Hashable, Sendable, LocalizedError {
    case noItemsSelected
    case nothingToCompress
    case nothingToUndo

    public var errorDescription: String? {
        switch self {
        case .noItemsSelected: "No items are selected."
        case .nothingToCompress: "None of the selected items can be compressed at this level."
        case .nothingToUndo: "There's nothing to undo."
        }
    }
}

/// An in-memory media library with simulated delete, compress, and undo.
///
/// This is a plain value type so it can be tested directly. `MockMediaLibraryService`
/// owns one and exposes it through the `MediaLibraryService` protocol.
public struct MediaLibrary: Sendable {
    private enum Change: Sendable {
        /// Removed items with their original positions, ascending.
        case deletion([(index: Int, item: MediaItem)], CleanupResult)
        /// Items as they were before compression.
        case compression(previous: [MediaItem], CleanupResult)
    }

    public private(set) var items: [MediaItem]
    public private(set) var savings = SessionSavings()
    private var history: [Change] = []

    public init(items: [MediaItem]) {
        self.items = items
    }

    public var canUndo: Bool { !history.isEmpty }

    /// The result of the action `undo()` would revert.
    public var lastResult: CleanupResult? {
        switch history.last {
        case .deletion(_, let result), .compression(_, let result): result
        case nil: nil
        }
    }

    public var summary: LibrarySummary { LibrarySummary(items: items) }

    public func items(withIDs ids: Set<MediaItem.ID>) -> [MediaItem] {
        items.filter { ids.contains($0.id) }
    }

    @discardableResult
    public mutating func delete(ids: Set<MediaItem.ID>) throws -> CleanupResult {
        var removed: [(index: Int, item: MediaItem)] = []
        var kept: [MediaItem] = []
        kept.reserveCapacity(items.count)
        for (index, item) in items.enumerated() {
            if ids.contains(item.id) {
                removed.append((index, item))
            } else {
                kept.append(item)
            }
        }
        guard !removed.isEmpty else { throw MediaLibraryError.noItemsSelected }

        let bytes = removed.reduce(Int64(0)) { $0 + $1.item.currentBytes }
        let result = CleanupResult(kind: .deletion, itemCount: removed.count, bytesRecovered: bytes)
        items = kept
        savings.deletedCount += removed.count
        savings.deletedBytes += bytes
        history.append(.deletion(removed, result))
        return result
    }

    @discardableResult
    public mutating func compress(ids: Set<MediaItem.ID>, level: CompressionLevel) throws -> CleanupResult {
        guard !ids.isEmpty else { throw MediaLibraryError.noItemsSelected }

        var previous: [MediaItem] = []
        var saved: Int64 = 0
        var matched = 0
        for index in items.indices where ids.contains(items[index].id) {
            matched += 1
            guard case .compressible(let newBytes, let savedBytes) = CompressionModel.estimate(for: items[index], level: level) else {
                continue
            }
            previous.append(items[index])
            items[index].currentBytes = newBytes
            items[index].compressionLevel = max(items[index].compressionLevel ?? level, level)
            saved += savedBytes
        }
        guard matched > 0 else { throw MediaLibraryError.noItemsSelected }
        guard !previous.isEmpty else { throw MediaLibraryError.nothingToCompress }

        let result = CleanupResult(
            kind: .compression(level),
            itemCount: previous.count,
            bytesRecovered: saved,
            skippedCount: matched - previous.count
        )
        savings.compressedCount += previous.count
        savings.compressedBytes += saved
        history.append(.compression(previous: previous, result))
        return result
    }

    /// Reverts the most recent delete or compress.
    @discardableResult
    public mutating func undo() throws -> CleanupResult {
        guard let change = history.popLast() else { throw MediaLibraryError.nothingToUndo }
        switch change {
        case .deletion(let removed, let result):
            // Ascending reinsertion restores each item to its exact original position.
            for entry in removed {
                items.insert(entry.item, at: entry.index)
            }
            savings.deletedCount -= result.itemCount
            savings.deletedBytes -= result.bytesRecovered
            return result
        case .compression(let previous, let result):
            let originals = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0) })
            for index in items.indices {
                if let original = originals[items[index].id] {
                    items[index] = original
                }
            }
            savings.compressedCount -= result.itemCount
            savings.compressedBytes -= result.bytesRecovered
            return result
        }
    }
}
