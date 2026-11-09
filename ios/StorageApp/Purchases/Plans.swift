import Foundation

/// Whether the paywall is live. While on, the shrink tools need Pro and
/// onboarding ends on the paywall.
///
/// Launch with `-paywallEnabled NO` to try the app with nothing gated (it
/// lands in UserDefaults' argument domain, like `ScreenshotRoute`).
enum PaywallConfig {
    static let isLaunched = true

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "paywallEnabled") as? Bool ?? isLaunched
    }

    /// Debug builds fake a purchase when the App Store has no products to sell,
    /// e.g. an xtool install on a free Apple ID. Release builds never do.
    static var allowsSimulatedPurchases: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    /// The website that hosts the legal and support pages (`web/`): the same
    /// origin as the site's `NEXT_PUBLIC_SITE_URL`. Change both together if
    /// the site moves to a custom domain.
    static let siteURL = URL(string: "https://simpleshrink.vercel.app")!

    /// Links App Review requires on a subscription paywall, plus support.
    /// The site's /terms page applies Apple's Standard EULA and adds to it.
    static let termsURL = siteURL.appending(path: "terms")
    static let privacyURL = siteURL.appending(path: "privacy")
    static let supportURL = siteURL.appending(path: "support")
}

/// What Pro can be bought as. Prices match web/src/lib/pricing.ts and
/// `Products.storekit`; on a real store the paywall shows `Product.displayPrice`.
///
/// The main paywall shows only `weekly` and `annual`. `lifetime` is offered
/// once, after someone dismisses the paywall without buying.
enum Plan: String, CaseIterable, Identifiable {
    case weekly
    case annual
    case lifetime

    var id: String { rawValue }

    static let paywallPlans: [Plan] = [.weekly, .annual]

    /// App Store Connect product IDs. Weekly and annual share one subscription
    /// group, so switching between them replaces rather than stacks.
    var productID: String {
        "com.example.storageapp.pro.\(rawValue)"
    }

    init?(productID: String) {
        guard let plan = Plan.allCases.first(where: { $0.productID == productID }) else { return nil }
        self = plan
    }

    var title: String {
        switch self {
        case .weekly: "Weekly"
        case .annual: "Annual"
        case .lifetime: "Lifetime"
        }
    }

    var price: Decimal {
        switch self {
        case .weekly: 6.99
        case .annual: 39.99
        case .lifetime: 49.99
        }
    }

    var displayPrice: String {
        price.formatted(.currency(code: "USD"))
    }

    /// "/week", "/year", or "once".
    var cadence: String {
        switch self {
        case .weekly: "/week"
        case .annual: "/year"
        case .lifetime: "once"
        }
    }

    var isSubscription: Bool { self != .lifetime }

    /// Annual price spread over a week, e.g. "$0.77".
    static var annualPerWeek: String {
        (Plan.annual.price / 52).formatted(.currency(code: "USD").precision(.fractionLength(2)))
    }

    /// How much annual saves against a year of weekly, rounded down.
    static var annualSavingsPercent: Int {
        savingsPercent(annual: Plan.annual.price, weekly: Plan.weekly.price)
    }

    /// How much `annual` saves against 52 weeks of `weekly`, rounded down.
    /// Prices in any one currency, e.g. a storefront's own.
    static func savingsPercent(annual: Decimal, weekly: Decimal) -> Int {
        let yearOfWeekly = weekly * 52
        guard yearOfWeekly > 0 else { return 0 }
        let ratio = NSDecimalNumber(decimal: 1 - annual / yearOfWeekly).doubleValue
        return max(0, Int((ratio * 100).rounded(.down)))
    }

    /// The App Store name for this plan, e.g. "Pro Annual".
    var storeName: String { "Pro \(title)" }

    /// What App Review asks a purchase screen to say (Guideline 3.1.2): the
    /// plan's name, its price and length, when payment is taken, and how
    /// auto-renewal works and is turned off. `price` is the formatted price.
    func disclosure(price: String) -> String {
        guard isSubscription else {
            return "\(storeName): one payment of \(price), charged to your Apple ID when you confirm. No subscription, nothing renews."
        }
        let period = self == .weekly ? "week" : "year"
        return "\(storeName): \(price) per \(period), charged to your Apple ID when you confirm. "
            + "It renews automatically each \(period) unless you cancel at least 24 hours before the current period ends. "
            + "Manage or cancel anytime in Settings > your name > Subscriptions."
    }

    /// The paywall's list. Matches the methods with `CleanupMethod.isPro`.
    static let proFeatures: [(symbol: String, text: String)] = [
        ("film", "Shrink 4K videos without deleting them"),
        ("scissors", "Trim long recordings to the good part"),
        ("livephoto", "Keep Live Photos as stills, minus the hidden video"),
        ("camera.viewfinder", "Re-save screenshots at a fraction of the size"),
        ("square.on.square", "Clear duplicates, blurry shots and junk"),
        ("wand.and.stars", "Clean up all your photos in one tap"),
    ]
}
