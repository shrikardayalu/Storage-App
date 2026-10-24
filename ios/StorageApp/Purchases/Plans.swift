import Foundation

/// Whether the paywall is live. Off until the app has been tested and pricing
/// is ready to launch; while off, nothing is gated and no paywall UI appears.
///
/// To try the flow without changing code, launch with `-paywallEnabled YES`
/// (it lands in UserDefaults' argument domain, like `ScreenshotRoute`).
enum PaywallConfig {
    static let isLaunched = false

    static var isEnabled: Bool {
        isLaunched || UserDefaults.standard.bool(forKey: "paywallEnabled")
    }
}

/// What Pro can be bought as. Prices match web/src/lib/pricing.ts.
///
/// The main paywall shows only `weekly` and `annual`. `lifetime` is offered
/// once, after someone dismisses the paywall without buying.
///
/// Purchases are simulated (`PurchaseStore`); swap in StoreKit product IDs and
/// `Product.displayPrice` before launch.
enum Plan: String, CaseIterable, Identifiable {
    case weekly
    case annual
    case lifetime

    var id: String { rawValue }

    static let paywallPlans: [Plan] = [.weekly, .annual]

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
        ("film","Shrink 4K videos without deleting them"),
        ("scissors", "Trim long recordings to the good part"),
        ("livephoto", "Keep Live Photos as stills"),
        ("photo.on.rectangle", "Re-save bloated screenshots"),
        ("square.stack.3d.up", "Pick the best shot from every burst"),
    ]
}
