import Foundation
import StorageCore

/// The first-run funnel: the hook and the pain (two screens), a live scan
/// that shows where the space went, then "which ones do you want to try?"
///
/// The person already knows their phone is full, so the funnel gets to their
/// own numbers fast and lets them pick what to do. Nothing in onboarding asks
/// for money: the picks are remembered, Home's plan leads with the free fix
/// that frees the most, and a Pro pick opens the paywall only when they tap
/// it, the moment they want it most. See `PlanOrder`.
enum OnboardingStep: Int, CaseIterable, Comparable {
    case hook
    case pain
    case scan
    case picks
    /// Only for the `paywall` screenshot route; the funnel never goes here.
    case paywall

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Steps that show in the pencil progress line at the top.
    static let tracked: [OnboardingStep] = [.hook, .pain, .scan, .picks]

    /// Share of the tracked steps done, 0 to 1.
    var progress: Double {
        guard let index = Self.tracked.firstIndex(of: self) else { return 1 }
        return Double(index + 1) / Double(Self.tracked.count)
    }

    /// Back never returns into the scan.
    var previous: OnboardingStep? {
        switch self {
        case .pain: .hook
        default: nil
        }
    }

    var canGoBack: Bool { previous != nil }

    /// The step after this one; nil means onboarding is done.
    var next: OnboardingStep? {
        switch self {
        case .hook: .pain
        case .pain: .scan
        case .scan: .picks
        case .picks, .paywall: nil
        }
    }
}

/// What the person picked, kept so Home can guide them through it.
struct OnboardingAnswers: Equatable {
    /// Ticked on "Which ones do you want to try?", in the order shown.
    var picks: [CleanupMethod] = []

    private enum Keys {
        static let picks = "onboarding.picks"
        static let completed = "onboarding.completed"
    }

    static func load(from defaults: UserDefaults = .standard) -> OnboardingAnswers {
        let raw = defaults.stringArray(forKey: Keys.picks) ?? []
        return OnboardingAnswers(picks: raw.compactMap(CleanupMethod.init(rawValue:)))
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(picks.map(\.rawValue), forKey: Keys.picks)
    }

    static func isCompleted(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: Keys.completed)
    }

    static func markCompleted(in defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: Keys.completed)
    }

    static let completedKey = Keys.completed
    static let picksKey = Keys.picks
    /// Set when the person closes Home's plan card.
    static let planDismissedKey = "home.planDismissed"
    /// Set once the paywall has followed a first free cleanup.
    static let winPaywallShownKey = "paywall.afterFirstWinShown"
}

/// The biggest kind of thing in a scan, for "Videos take 64% of it".
struct Bloat: Equatable {
    let group: ScanGroup
    let bytes: Int64
    let share: Double

    var percent: Int { Int((share * 100).rounded()) }

    init?(scan: LibraryScan) {
        let total = scan.total.bytes
        guard total > 0, let top = ScanGroup.kinds.max(by: { scan[$0].bytes < scan[$1].bytes }) else { return nil }
        group = top
        bytes = scan[top].bytes
        share = Double(bytes) / Double(total)
    }

    /// Why that kind of thing is worth a look, in one line.
    var why: String {
        switch group {
        case .videos: "Big videos are usually the fastest way to get space back."
        case .livePhotos: "Every Live Photo hides a short video clip."
        case .photos: "Copies and blurry shots add up quietly."
        case .bursts: "Most of a burst is shots you'll never look at."
        case .screenshots: "Old screenshots are usually safe to clear."
        case .bigFormats: "4K and ProRes files are huge."
        }
    }
}

/// A typical iPhone photo, for "room for about N more photos". Kept on the
/// large side so the figure never overpromises.
let typicalPhotoBytes: Int64 = 3_500_000

/// "Room for about N more photos" for a number of bytes, rounded down.
func morePhotos(_ bytes: Int64) -> Int { roughCount(Int(max(bytes, 0) / typicalPhotoBytes)) }

/// How long the phone's free space lasts, for the pain screen.
struct StorageRunway: Equatable {
    let photos: Int
    let videoMinutes: Int

    /// A minute of 4K at 30 fps in HEVC, Apple's own figure.
    static let fourKMinuteBytes: Int64 = 170_000_000

    init(availableBytes: Int64) {
        let free = max(availableBytes, 0)
        photos = roughCount(Int(free / typicalPhotoBytes))
        videoMinutes = Int(free / Self.fourKMinuteBytes)
    }
}

/// Rounded down so it reads like an estimate and never overpromises.
func roughCount(_ raw: Int) -> Int {
    switch raw {
    case ..<20: raw
    case ..<200: raw / 10 * 10
    case ..<2000: raw / 50 * 50
    default: raw / 100 * 100
    }
}
