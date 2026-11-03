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

    /// Links App Review requires on a subscription paywall. Terms are Apple's
    /// standard EULA until the site has its own; update the privacy link when
    /// the site's real domain is set.
    static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let privacyURL = URL(string: "https://storageapp.example.com/privacy")!
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
        let yearOfWeekly = Plan.weekly.price * 52
        let ratio = NSDecimalNumber(decimal: 1 - Plan.annual.price / yearOfWeekly).doubleValue
        return Int((ratio * 100).rounded(.down))
    }

    static let proFeatures: [(symbol: String, text: String)] = [
        ("film", "Shrink 4K videos without deleting them"),
        ("scissors", "Trim long recordings to the good part"),
        ("livephoto", "Keep Live Photos as stills"),
        ("square.stack.3d.up", "Pick the best shot from every burst"),
    ]
}
