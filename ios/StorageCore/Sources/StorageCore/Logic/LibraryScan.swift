import Foundation

/// How a scan sorts what it found. The first five groups don't overlap, so
/// their totals add up to the whole scan; `bigFormats` cuts across them.
public enum ScanGroup: String, CaseIterable, Hashable, Sendable, Identifiable {
    case photos
    case livePhotos
    case bursts
    case screenshots
    case videos
    case bigFormats

    public var id: String { rawValue }

    /// The groups that don't overlap: every item is in exactly one.
    public static let kinds: [ScanGroup] = [.photos, .livePhotos, .bursts, .screenshots, .videos]

    /// Videos at least this long on their long side count as 4K.
    public static let fourKLongSide = 3840

    public var title: String {
        switch self {
        case .photos: "Photos"
        case .livePhotos: "Live Photos"
        case .bursts: "Bursts"
        case .screenshots: "Screenshots"
        case .videos: "Videos"
        case .bigFormats: "Big Formats"
        }
    }

    public var detail: String {
        switch self {
        case .photos: "Still photos"
        case .livePhotos: "A photo plus a short video"
        case .bursts: "Rapid shots, usually one keeper"
        case .screenshots: "Usually safe to clear"
        case .videos: "Every video"
        case .bigFormats: "4K, slo-mo, ProRes and ProRAW"
        }
    }

    /// The one non-overlapping group an item belongs to.
    public static func kind(of item: MediaItem) -> ScanGroup {
        switch item.category {
        case .screenshot: .screenshots
        case .video: .videos
        case .photo:
            if item.burstID != nil {
                .bursts
            } else if item.traits.contains(.livePhoto) {
                .livePhotos
            } else {
                .photos
            }
        }
    }

    public static func isBigFormat(_ item: MediaItem) -> Bool {
        switch item.format {
        case .proRAW, .proRes:
            return true
        default:
            guard item.category == .video else { return false }
            return item.traits.contains(.slowMotion) || max(item.pixelWidth, item.pixelHeight) >= fourKLongSide
        }
    }

    public func includes(_ item: MediaItem) -> Bool {
        self == .bigFormats ? Self.isBigFormat(item) : Self.kind(of: item) == self
    }
}

/// The result of scanning part of the photo library: every item biggest
/// first, with totals per group. Scanning only reads; it changes nothing.
public struct LibraryScan: Hashable, Sendable {
    public let date: Date
    /// Biggest first, with the ID as a tie-breaker so the order is stable.
    public let items: [MediaItem]
    public let total: CategoryTotal
    public let groups: [ScanGroup: CategoryTotal]
    /// Distinct bursts, as opposed to shots in bursts (`self[.bursts].count`).
    public let burstCount: Int

    public init(items: [MediaItem], date: Date = Date()) {
        var total = CategoryTotal()
        var groups: [ScanGroup: CategoryTotal] = [:]
        for item in items {
            total.count += 1
            total.bytes += item.currentBytes
            for group in ScanGroup.allCases where group.includes(item) {
                groups[group, default: .zero].count += 1
                groups[group, default: .zero].bytes += item.currentBytes
            }
        }
        self.date = date
        self.items = items.sorted(by: MediaSort.largestFirst.areInIncreasingOrder)
        self.total = total
        self.groups = groups
        self.burstCount = Set(items.compactMap(\.burstID)).count
    }

    public subscript(group: ScanGroup) -> CategoryTotal {
        groups[group] ?? .zero
    }

    /// Items in `group`, or every item when `group` is nil. Biggest first.
    public func items(in group: ScanGroup?) -> [MediaItem] {
        guard let group else { return items }
        return items.filter(group.includes)
    }
}
