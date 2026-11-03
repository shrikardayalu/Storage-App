import Foundation

/// Which kind of action gave space back, for the results screen's breakdown.
public enum FreedSource: String, Codable, CaseIterable, Sendable {
    /// Deleting photos, Live Photos → stills, bursts, duplicates and junk.
    case photos
    /// Smaller or trimmed videos.
    case videos
    /// Files deleted from a folder the person picked.
    case files
    /// Guides for things only the person can do (WhatsApp, Messages, Settings…).
    case guides
    /// A restart, measured on the next open.
    case restart
}

/// One action and the free space it gave back, measured against the reading
/// taken right before it.
public struct FreedEntry: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let source: FreedSource
    /// What was done, e.g. "Deleted 3 items" or "WhatsApp".
    public let title: String
    /// Free space right before the action.
    public let baseline: StorageSnapshot
    /// What the action should give back; 0 when nobody can know in advance
    /// (guides, restart). Measurements never count more than this.
    public let expectedBytes: Int64
    /// The most free space this action has been seen to give back.
    public fileprivate(set) var measuredBytes: Int64 = 0
    /// Still being measured. Closed entries keep their figure.
    public fileprivate(set) var isOpen = true

    public init(id: UUID = UUID(), source: FreedSource, title: String, baseline: StorageSnapshot, expectedBytes: Int64) {
        self.id = id
        self.source = source
        self.title = title
        self.baseline = baseline
        self.expectedBytes = expectedBytes
    }

    /// Measured, and big enough to tell apart from free space moving on its own.
    public var counts: Bool {
        expectedBytes > 0 ? measuredBytes > 0 : measuredBytes >= FreedLedger.noiseFloor
    }
}

/// Every action's measured gain, oldest first, so the results screen can show
/// a total that matches the real change in free space. Pure value logic; the
/// app decides where it's saved.
///
/// Free space is shared, so actions whose measuring overlaps would count the
/// same bytes twice. Each reading is shared out newest action first: an
/// action only gets what's left after everything that started after it took
/// its share. Actions with a known size never get more than that size.
public struct FreedLedger: Codable, Equatable, Sendable {
    /// Free space moves by a few megabytes on its own (caches, logs). Unknown-size
    /// gains below this aren't counted.
    public static let noiseFloor: Int64 = 20_000_000
    /// The oldest entries are dropped past this count.
    public static let maximumCount = 500

    public private(set) var entries: [FreedEntry]

    public init(entries: [FreedEntry] = []) {
        self.entries = Array(entries.sorted { $0.baseline.date < $1.baseline.date }.suffix(Self.maximumCount))
    }

    /// How long an action keeps being measured before its figure is final.
    /// Photos wait in Recently Deleted for up to 30 days; files come back at
    /// once; guides and restarts are measured while the person is on them.
    public static func window(for source: FreedSource) -> TimeInterval {
        switch source {
        case .photos, .videos: 30 * 86_400
        case .files: 10 * 60
        case .guides, .restart: 86_400
        }
    }

    public subscript(id: FreedEntry.ID) -> FreedEntry? {
        entries.first { $0.id == id }
    }

    /// Starts measuring an action from `baseline`. Returns the new entry's ID.
    @discardableResult
    public mutating func open(_ source: FreedSource, title: String, baseline: StorageSnapshot, expectedBytes: Int64 = 0) -> FreedEntry.ID {
        let entry = FreedEntry(source: source, title: title, baseline: baseline, expectedBytes: max(0, expectedBytes))
        let index = entries.lastIndex { $0.baseline.date <= baseline.date }.map { $0 + 1 } ?? 0
        entries.insert(entry, at: index)
        if entries.count > Self.maximumCount {
            entries.removeFirst(entries.count - Self.maximumCount)
        }
        return entry.id
    }

    /// Stops measuring an action. An action that gave nothing back is dropped,
    /// so the results only list what freed space.
    public mutating func close(_ id: FreedEntry.ID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        if entries[index].counts {
            entries[index].isOpen = false
        } else {
            entries.remove(at: index)
        }
    }

    /// Closes actions measured long enough, shares a new free-space reading out
    /// among the rest, then closes any that reached their expected size.
    public mutating func record(_ snapshot: StorageSnapshot) {
        // A reading after an action's window says nothing about that action.
        for entry in entries where entry.isOpen && snapshot.date.timeIntervalSince(entry.baseline.date) > Self.window(for: entry.source) {
            close(entry.id)
        }
        // Newest first, so older actions only get what newer ones didn't take.
        for index in entries.indices.reversed() where entries[index].isOpen {
            let entry = entries[index]
            guard snapshot.date >= entry.baseline.date else { continue }
            let takenByNewer = entries[(index + 1)...].reduce(Int64(0)) { $0 + $1.measuredBytes }
            var gain = max(0, snapshot.availableBytes - entry.baseline.availableBytes - takenByNewer)
            if entry.expectedBytes > 0 { gain = min(gain, entry.expectedBytes) }
            // Space that came back stays counted even if free space dips again later.
            entries[index].measuredBytes = max(entry.measuredBytes, gain)
        }
        for entry in entries where entry.isOpen && entry.expectedBytes > 0 && entry.measuredBytes >= entry.expectedBytes {
            close(entry.id)
        }
    }

    /// The actions that gave space back, newest first.
    public var counted: [FreedEntry] {
        entries.filter(\.counts).reversed()
    }

    /// Everything the app has measured coming back.
    public var total: Int64 {
        counted.reduce(0) { $0 + $1.measuredBytes }
    }

    public func total(for source: FreedSource) -> Int64 {
        counted.filter { $0.source == source }.reduce(0) { $0 + $1.measuredBytes }
    }

    /// Free space right before the first action.
    public var start: StorageSnapshot? {
        entries.first?.baseline
    }

    /// The real change in free space since right before the first action, to
    /// check the total against. Other apps, downloads and iOS move it too, so
    /// it only matches the total when nothing else happened in between.
    public func freeSpaceChange(now: StorageSnapshot) -> Int64? {
        guard let start, now.date >= start.date else { return nil }
        return now.availableBytes - start.availableBytes
    }
}
