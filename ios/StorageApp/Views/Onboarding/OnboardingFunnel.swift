import Foundation
import StorageCore

/// The first-run funnel: hook, the pain, one quick question, the "shrink,
/// don't delete" demo, the Photos permission, a live scan, the reveal of
/// what could be freed, then the paywall.
///
/// The order follows what the best-converting utility apps share: show the
/// problem with the person's own numbers, make the pain felt before asking
/// for anything, keep questions to one easy tap, explain a permission before
/// iOS asks for it, and put the paywall straight after the moment they see
/// their own result, the "aha", instead of before it.
enum OnboardingStep: Int, CaseIterable, Comparable {
    case hook
    case pain
    case goal
    case shrink
    case privacy
    case scan
    case reveal
    case paywall

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Steps that show in the pencil progress line at the top.
    static let tracked: [OnboardingStep] = [.hook, .pain, .goal, .shrink, .privacy, .scan, .reveal]

    /// Share of the tracked steps done, 0 to 1.
    var progress: Double {
        guard let index = Self.tracked.firstIndex(of: self) else { return 1 }
        return Double(index + 1) / Double(Self.tracked.count)
    }

    /// Back goes to the previous question, never back into the scan.
    var canGoBack: Bool {
        switch self {
        case .pain, .goal, .shrink, .privacy: true
        default: false
        }
    }

    var previous: OnboardingStep? {
        canGoBack ? OnboardingStep(rawValue: rawValue - 1) : nil
    }

    /// The step after this one. The paywall is skipped for anyone who already
    /// has Pro or while the paywall is switched off; nil means onboarding is done.
    func next(showsPaywall: Bool) -> OnboardingStep? {
        switch self {
        case .reveal: showsPaywall ? .paywall : nil
        case .paywall: nil
        default: OnboardingStep(rawValue: rawValue + 1)
        }
    }
}

/// "What do you need the space for?" One answer.
enum SpaceGoal: String, CaseIterable, Identifiable, Codable {
    case update
    case newMemories
    case quietAlerts
    case tidy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .update: "An iOS update"
        case .newMemories: "New photos & videos"
        case .quietAlerts: "Stop the \u{201C}Storage Full\u{201D} alerts"
        case .tidy: "Just a tidier phone"
        }
    }

    var symbol: String {
        switch self {
        case .update: "arrow.down.circle"
        case .newMemories: "camera"
        case .quietAlerts: "bell.slash"
        case .tidy: "wand.and.stars"
        }
    }

    /// Ends the reveal's headline: "You could free up 4.2 GB …"
    var revealPhrase: String {
        switch self {
        case .update: "for your next iOS update"
        case .newMemories: "for new photos and videos"
        case .quietAlerts: "to quiet the Storage Full alerts"
        case .tidy: "and tidy up your library"
        }
    }
}

/// The person's answer, kept so later screens can speak to it.
struct OnboardingAnswers: Equatable {
    var goal: SpaceGoal?

    private enum Keys {
        static let goal = "onboarding.goal"
        static let completed = "onboarding.completed"
    }

    static func load(from defaults: UserDefaults = .standard) -> OnboardingAnswers {
        OnboardingAnswers(goal: defaults.string(forKey: Keys.goal).flatMap(SpaceGoal.init(rawValue:)))
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(goal?.rawValue, forKey: Keys.goal)
    }

    static func isCompleted(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: Keys.completed)
    }

    static func markCompleted(in defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: Keys.completed)
    }

    static let completedKey = Keys.completed
}

/// The numbers the reveal shows, from a finished scan.
struct RevealNumbers: Equatable {
    /// Deleting suggested duplicates and junk (free).
    var freeBytes: Int64
    /// Shrinking videos, Live Photos to stills, best shot of each burst (Pro).
    var proBytes: Int64

    var totalBytes: Int64 { freeBytes + proBytes }
    var isEmpty: Bool { totalBytes <= 0 }

    /// A typical iPhone photo, for "room for about N more photos". Kept on
    /// the large side so the figure never overpromises.
    static let typicalPhotoBytes: Int64 = 3_500_000

    var morePhotos: Int { roughCount(Int(totalBytes / Self.typicalPhotoBytes)) }

    static let sample = RevealNumbers(freeBytes: 1_180_000_000, proBytes: 3_420_000_000)
}

/// How long the phone's free space lasts, for the pain screen.
struct StorageRunway: Equatable {
    let photos: Int
    let videoMinutes: Int

    /// A minute of 4K at 30 fps in HEVC, Apple's own figure.
    static let fourKMinuteBytes: Int64 = 170_000_000

    init(availableBytes: Int64) {
        let free = max(availableBytes, 0)
        photos = roughCount(Int(free / RevealNumbers.typicalPhotoBytes))
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
