import Foundation

/// The shots of one burst in the test album, oldest first.
public struct Burst: Identifiable, Hashable, Sendable {
    /// The burst identifier every shot shares.
    public let id: String
    public let shots: [MediaItem]

    public init(id: String, shots: [MediaItem]) {
        self.id = id
        self.shots = shots.sorted { ($0.creationDate, $0.id) < ($1.creationDate, $1.id) }
    }

    /// The shot to keep unless the person picks another: the one they or the
    /// camera marked as the pick, otherwise the middle shot.
    public var suggestedKeeper: MediaItem.ID {
        shots.first { $0.traits.contains(.burstPick) }?.id ?? shots[shots.count / 2].id
    }

    /// Space freed by keeping `keeper` and removing every other shot.
    public func savedBytes(keeping keeper: MediaItem.ID) -> Int64 {
        shots.filter { $0.id != keeper }.reduce(0) { $0 + $1.currentBytes }
    }

    /// Every burst in `items` with at least two shots, biggest saving first.
    /// A burst already down to one shot has nothing left to clean.
    public static func all(in items: [MediaItem]) -> [Burst] {
        Dictionary(grouping: items.filter { $0.burstID != nil }, by: { $0.burstID! })
            .map { Burst(id: $0.key, shots: $0.value) }
            .filter { $0.shots.count > 1 }
            .sorted { ($0.savedBytes(keeping: $0.suggestedKeeper), $1.id) > ($1.savedBytes(keeping: $1.suggestedKeeper), $0.id) }
    }
}

/// What a burst cleanup will do, worked out from the album as it is right
/// before the change: for each burst with a keeper, every other shot goes.
public struct BurstPlan: Hashable, Sendable {
    /// Burst ID → the one shot the person picked to keep.
    public let keepers: [String: MediaItem.ID]
    /// Every other shot of those bursts.
    public let remove: Set<MediaItem.ID>

    /// Builds the plan from the album's current members, and refuses if it
    /// isn't exactly what the person reviewed.
    /// - Parameters:
    ///   - keep: the shots the person picked, one per burst.
    ///   - expectedRemove: the shots the review screen said would go.
    ///   - members: every item in the test album right now, ID → burst ID (nil if not in a burst).
    public static func make(
        keep: Set<MediaItem.ID>,
        expectedRemove: Set<MediaItem.ID>,
        members: [MediaItem.ID: String?]
    ) throws -> BurstPlan {
        guard !keep.isEmpty else { throw PhotoChangeError.burstsChanged("No shots were picked to keep.") }
        var keepers: [String: MediaItem.ID] = [:]
        for id in keep {
            guard let entry = members[id] else {
                throw PhotoChangeError.burstsChanged("A shot you picked to keep is no longer in \u{201C}\(TestMode.albumName)\u{201D}.")
            }
            guard let burst = entry else {
                throw PhotoChangeError.burstsChanged("A shot you picked to keep isn't part of a burst.")
            }
            guard keepers[burst] == nil else {
                throw PhotoChangeError.burstsChanged("Two shots were picked to keep in the same burst.")
            }
            keepers[burst] = id
        }
        let remove = Set(members.compactMap { id, burst in
            burst.flatMap { keepers[$0] }.flatMap { $0 == id ? nil : id }
        })
        guard remove == expectedRemove else {
            throw PhotoChangeError.burstsChanged("The bursts in \u{201C}\(TestMode.albumName)\u{201D} changed since the scan.")
        }
        guard !remove.isEmpty else { throw PhotoChangeError.burstsChanged("Those bursts have nothing left to remove.") }
        return BurstPlan(keepers: keepers, remove: remove)
    }
}

/// Proof of a burst cleanup: for every burst touched, exactly one shot is
/// left, and it's the one the person picked.
public struct BurstReceipt: Hashable, Sendable {
    /// Burst ID → the shot that was kept.
    public let keepers: [String: MediaItem.ID]
    public let removed: Set<MediaItem.ID>
    public let removedBytes: Int64
    public let albumCountBefore: Int
    public let albumCountAfter: Int
    /// Bursts where the picked shot, and only it, is left.
    public let keptPick: Set<String>
    /// True when the album after is the album before minus exactly the removed shots.
    public let onlyApprovedRemoved: Bool

    /// True when every burst has only its picked shot left, and nothing else changed.
    public var isExact: Bool {
        onlyApprovedRemoved && keptPick == Set(keepers.keys)
    }

    public init(
        keepers: [String: MediaItem.ID],
        removed: Set<MediaItem.ID>,
        removedBytes: Int64,
        albumCountBefore: Int,
        albumCountAfter: Int,
        keptPick: Set<String>,
        onlyApprovedRemoved: Bool
    ) {
        self.keepers = keepers
        self.removed = removed
        self.removedBytes = removedBytes
        self.albumCountBefore = albumCountBefore
        self.albumCountAfter = albumCountAfter
        self.keptPick = keptPick
        self.onlyApprovedRemoved = onlyApprovedRemoved
    }

    /// Compares the album's members before and after the cleanup.
    public static func audit(
        plan: BurstPlan,
        before: [MediaItem.ID: String?],
        after: [MediaItem.ID: String?],
        removedBytes: Int64
    ) -> BurstReceipt {
        let beforeIDs = Set(before.keys)
        let afterIDs = Set(after.keys)
        let keptPick = Set(plan.keepers.compactMap { burst, keeper in
            let left = after.filter { $0.value == burst }.map(\.key)
            return left == [keeper] ? burst : nil
        })
        return BurstReceipt(
            keepers: plan.keepers,
            removed: beforeIDs.subtracting(afterIDs),
            removedBytes: removedBytes,
            albumCountBefore: before.count,
            albumCountAfter: after.count,
            keptPick: keptPick,
            onlyApprovedRemoved: afterIDs == beforeIDs.subtracting(plan.remove)
        )
    }
}
