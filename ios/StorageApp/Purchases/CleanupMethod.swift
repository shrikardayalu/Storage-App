import Foundation
import StorageCore

/// The ways SimpleShrink frees space, as onboarding suggests them and Home
/// lists them. Which ones need Pro is decided here, in `isPro`, and nowhere
/// else: onboarding's picks, Home's cards and the plan card all read it.
///
/// The split: free does it by hand, Pro does the heavy hitters and does
/// them in one tap.
enum CleanupMethod: String, CaseIterable, Identifiable, Codable {
    case shrinkVideos
    case photoCleanup
    case duplicates
    case livePhotos
    case screenshots
    case swipe
    case bursts
    case chatAttachments

    var id: String { rawValue }

    /// `Plan.proFeatures` lists the Pro ones on the paywall; keep it in step.
    var isPro: Bool {
        switch self {
        case .shrinkVideos, .photoCleanup, .duplicates, .livePhotos, .screenshots: true
        case .swipe, .bursts, .chatAttachments: false
        }
    }

    /// What onboarding offers. One-tap Photo Cleanup stands in for its parts
    /// (Live Photos, duplicates, junk) so the list doesn't count them twice.
    static let onboardingChoices: [CleanupMethod] = [.shrinkVideos, .photoCleanup, .screenshots, .swipe, .bursts, .chatAttachments]

    var title: String {
        switch self {
        case .shrinkVideos: "Shrink & trim videos"
        case .photoCleanup: "One-tap Photo Cleanup"
        case .duplicates: "Duplicates and junk"
        case .livePhotos: "Live Photos \u{2192} stills"
        case .screenshots: "Re-save screenshots"
        case .swipe: "Swipe to clean"
        case .bursts: "Best shot of each burst"
        case .chatAttachments: "Old Messages attachments"
        }
    }

    /// One line under the title in onboarding's picks and Home's plan.
    var pitch: String {
        switch self {
        case .shrinkVideos: "Same videos, a fraction of the size"
        case .photoCleanup: "Live Photos to stills, duplicates and junk, all at once"
        case .duplicates: "Copies, blurry shots, old screenshots"
        case .livePhotos: "Keep the photo, drop the hidden video clip"
        case .screenshots: "Same screenshots, a fraction of the size"
        case .swipe: "Likely deletes, one at a time. Swipe left to delete"
        case .bursts: "Keep the best shot, clear the rest"
        case .chatAttachments: "We'll show you where they pile up"
        }
    }

    var illustration: Illustration {
        switch self {
        case .shrinkVideos: .compress
        case .photoCleanup: .phoneSparkle
        case .duplicates: .beaker
        case .livePhotos: .photo
        case .screenshots: .screenshot
        case .swipe: .trash
        case .bursts: .stackSmall
        case .chatAttachments: .screenshot
        }
    }

    /// Methods the person does themselves in another app, with our steps.
    var guide: OtherAppGuide? {
        self == .chatAttachments ? .messages : nil
    }

    /// Methods whose saving is already counted by another one in the list,
    /// so totals don't add the same photos twice.
    var coveredBy: [CleanupMethod] {
        switch self {
        case .duplicates, .livePhotos: [.photoCleanup]
        // Old PNG screenshots Photo Cleanup would remove aren't counted again for re-saving.
        case .screenshots: [.photoCleanup]
        case .swipe: [.photoCleanup, .duplicates]
        default: []
        }
    }
}

/// One thing worth doing after a scan, and what it could free.
struct Suggestion: Equatable, Identifiable {
    let method: CleanupMethod
    /// nil when it can't be measured from here (a guide for another app).
    let bytes: Int64?

    var id: CleanupMethod { method }

    /// Worth showing: measured with something to free, or a guide.
    var isWorthDoing: Bool {
        bytes.map { $0 > 0 } ?? (method.guide != nil)
    }

    /// The ones worth doing, biggest saving first; guides with no number go last.
    static func ranked(_ all: [Suggestion]) -> [Suggestion] {
        let worth = Array(all.filter(\.isWorthDoing).enumerated())
        return worth.sorted { lhs, rhs -> Bool in
            switch (lhs.element.bytes, rhs.element.bytes) {
            case let (left?, right?) where left != right: return left > right
            case (.some, .none): return true
            case (.none, .some): return false
            default: return lhs.offset < rhs.offset
            }
        }.map(\.element)
    }

    /// For screenshots and previews, which have no library to scan.
    static let sample: [Suggestion] = [
        Suggestion(method: .shrinkVideos, bytes: 2_860_000_000),
        Suggestion(method: .photoCleanup, bytes: 1_600_000_000),
        Suggestion(method: .swipe, bytes: 1_180_000_000),
        Suggestion(method: .bursts, bytes: 140_000_000),
        Suggestion(method: .chatAttachments, bytes: nil),
    ]
}

extension [Suggestion] {
    /// Everything measured, added up once: a method covered by another one
    /// in the list (swipe inside Photo Cleanup, say) isn't counted again.
    var totalBytes: Int64 {
        let methods = Set(map(\.method))
        return filter { !$0.method.coveredBy.contains(where: methods.contains) }
            .reduce(0) { $0 + ($1.bytes ?? 0) }
    }
}

/// The order Home's plan walks through the picks.
///
/// On the free tier, every free fix comes first, biggest first, so the first
/// thing someone does is something they can actually do. Pro picks wait
/// after them, and open the paywall when tapped: that's the moment they want
/// it most. Once Pro is unlocked, the Pro tools lead, biggest first, since
/// they do the heavy lifting in one tap; free fixes follow.
enum PlanOrder {
    /// A free fix "makes a dent" at 1% of the album, capped at 250 MB. When no
    /// free pick does, the swipe feed is added up front so a single tiny burst
    /// never leads on its own.
    static func threshold(albumBytes: Int64) -> Int64 {
        max(1, min(250_000_000, albumBytes / 100))
    }

    static func build(picks: [CleanupMethod], saving: (CleanupMethod) -> Int64?, albumBytes: Int64, hasPro: Bool) -> [CleanupMethod] {
        // Biggest first; not yet measured goes last; ties keep the pick order.
        func bySaving(_ list: [CleanupMethod]) -> [CleanupMethod] {
            list.enumerated().sorted { lhs, rhs in
                let (a, b) = (saving(lhs.element) ?? -1, saving(rhs.element) ?? -1)
                return a != b ? a > b : lhs.offset < rhs.offset
            }.map(\.element)
        }
        let free = bySaving(picks.filter { !$0.isPro && $0.guide == nil })
        let guides = picks.filter { $0.guide != nil }
        let pro = bySaving(picks.filter(\.isPro))
        if hasPro {
            return pro + free + guides
        }
        let line = threshold(albumBytes: albumBytes)
        let makesDent = free.contains { (saving($0) ?? 0) >= line }
        // Nothing free makes a dent: the swipe feed always has something to show.
        let lead: [CleanupMethod] = !makesDent && !picks.contains(.swipe) && saving(.swipe) != 0 ? [.swipe] : []
        return lead + free + guides + pro
    }
}

/// What one-tap Photo Cleanup will do: remove the suggested duplicates and
/// junk (best copy of each duplicate kept; receipts and documents left
/// alone), and turn the remaining Live Photos into stills.
struct PhotoCleanupPlan: Equatable {
    var remove: Set<MediaItem.ID>
    var keepers: Set<MediaItem.ID>
    var convert: Set<MediaItem.ID>
    var removeBytes: Int64
    var convertBytes: Int64

    var totalBytes: Int64 { removeBytes + convertBytes }
    var isEmpty: Bool { remove.isEmpty && convert.isEmpty }

    /// Live Photos made into stills, removed copies, and other junk, as counts for the summary.
    var stillCount: Int { convert.count }
    var copyCount: Int
    var copyBytes: Int64
    var junkCount: Int { remove.count - copyCount }
    var junkBytes: Int64 { removeBytes - copyBytes }

    /// - Parameter blocked: photos the album check won't let the app touch.
    ///   A duplicate with a blocked extra copy is left alone entirely.
    init(report: JunkReport, livePhotos: [MediaItem], blocked: Set<MediaItem.ID> = []) {
        var remove = Set<MediaItem.ID>()
        var removeBytes: Int64 = 0
        var keepers = Set<MediaItem.ID>()
        for group in report.duplicates {
            let extras = group.items.filter { $0.id != group.suggestedKeeper }
            guard !extras.contains(where: { blocked.contains($0.id) }) else { continue }
            keepers.insert(group.suggestedKeeper)
            for item in extras {
                remove.insert(item.id)
                removeBytes += item.currentBytes
            }
        }
        let copyCount = remove.count
        let copyBytes = removeBytes
        for finding in report.findings where finding.reason.startsSelected && !blocked.contains(finding.id) {
            remove.insert(finding.id)
            removeBytes += finding.item.currentBytes
        }
        let converting = livePhotos.filter { !remove.contains($0.id) && !blocked.contains($0.id) }
        self.remove = remove
        self.keepers = keepers
        self.copyCount = copyCount
        self.copyBytes = copyBytes
        self.convert = Set(converting.map(\.id))
        self.removeBytes = removeBytes
        self.convertBytes = converting.reduce(0) { $0 + $1.livePhotoVideoBytes }
    }
}

/// One photo in the swipe feed, and why it's there.
struct SwipeCandidate: Identifiable, Equatable {
    let item: MediaItem
    let reason: String
    /// For a duplicate: the copy that stays, whatever happens to this one.
    let keeper: MediaItem.ID?

    var id: MediaItem.ID { item.id }

    /// Every suggestion from the junk report, one photo each, biggest first.
    /// Duplicates show only their extra copies; the best copy never appears.
    static func all(from report: JunkReport) -> [SwipeCandidate] {
        let copies = report.duplicates.flatMap { group in
            group.items.filter { $0.id != group.suggestedKeeper }.map {
                SwipeCandidate(item: $0, reason: group.isExact ? "An exact copy. The best one stays" : "Nearly the same as another shot",
                               keeper: group.suggestedKeeper)
            }
        }
        let singles = report.findings.map { SwipeCandidate(item: $0.item, reason: $0.reason.title, keeper: nil) }
        return (copies + singles).sorted { ($0.item.currentBytes, $1.id) > ($1.item.currentBytes, $0.id) }
    }
}

extension AppModel {
    /// What a method could free in the scanned album. nil when it can't be
    /// measured: a guide, or anything that needs the photos checked first.
    func saving(for method: CleanupMethod) -> Int64? {
        switch method {
        case .shrinkVideos: videoSaving
        case .photoCleanup: photoCleanupPlan?.totalBytes
        case .duplicates: junkSaving
        case .livePhotos: livePhotoSaving
        case .screenshots: screenshotSaving
        case .swipe: swipeSaving
        case .bursts: burstSaving
        case .chatAttachments: nil
        }
    }

    /// What onboarding suggests after a scan, biggest saving first.
    var suggestions: [Suggestion] {
        Suggestion.ranked(CleanupMethod.onboardingChoices.map { Suggestion(method: $0, bytes: saving(for: $0)) })
    }

    /// Everything the Pro tools could free in the scanned album, counted once.
    var proSaving: Int64 {
        let removed = photoCleanupPlan?.remove ?? []
        // Screenshots Photo Cleanup would remove aren't counted again for re-saving.
        let screenshots = resavableScreenshots.filter { !removed.contains($0.id) }
            .reduce(Int64(0)) { $0 + ScreenshotResave.estimatedSaving(for: $1) }
        return [CleanupMethod.shrinkVideos, .photoCleanup].reduce(screenshots) { $0 + (saving(for: $1) ?? 0) }
    }

    /// The plan card's order for these picks: free fixes first on the free
    /// tier, Pro tools first once Pro is unlocked.
    func planOrder(_ picks: [CleanupMethod], hasPro: Bool) -> [CleanupMethod] {
        PlanOrder.build(picks: picks, saving: { saving(for: $0) }, albumBytes: libraryScan?.total.bytes ?? 0, hasPro: hasPro)
    }
}
