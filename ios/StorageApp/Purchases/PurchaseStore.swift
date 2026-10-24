import Foundation
import Observation

/// Who has Pro, and the simulated purchase flow.
///
/// Every purchase here is a dummy: tapping buy waits briefly and grants the
/// plan, with no StoreKit and no charge. The granted plan is remembered in
/// UserDefaults so it survives relaunches. Replace `purchase(_:)` and
/// `restore()` with StoreKit 2 before launch.
@MainActor
@Observable
final class PurchaseStore {
    private(set) var activePlan: Plan?
    private(set) var isPurchasing = false

    @ObservationIgnored private let defaults: UserDefaults

    private enum Keys {
        static let activePlan = "purchases.activePlan"
        static let lifetimeOfferShown = "purchases.lifetimeOfferShown"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        activePlan = defaults.string(forKey: Keys.activePlan).flatMap(Plan.init(rawValue:))
    }

    var isPro: Bool { activePlan != nil }

    /// True when a Pro feature should open the paywall instead of running.
    var requiresPro: Bool { PaywallConfig.isEnabled && !isPro }

    /// The lifetime deal is a one-time offer: shown after the first paywall
    /// dismissal, then never again.
    var canShowLifetimeOffer: Bool {
        !isPro && !defaults.bool(forKey: Keys.lifetimeOfferShown)
    }

    func markLifetimeOfferShown() {
        defaults.set(true, forKey: Keys.lifetimeOfferShown)
    }

    /// Simulated purchase: always succeeds and grants `plan`.
    func purchase(_ plan: Plan) async {
        isPurchasing = true
        defer { isPurchasing = false }
        try? await Task.sleep(for: .milliseconds(700))

        activePlan = plan
        defaults.set(plan.rawValue, forKey: Keys.activePlan)
    }

    /// Simulated restore: there's no store to ask, so this only reports
    /// whether a plan was already granted on this device.
    func restore() async -> Bool {
        isPurchasing = true
        defer { isPurchasing = false }
        try? await Task.sleep(for: .milliseconds(500))
        return isPro
    }

    /// Clears the granted plan and the one-time offer, for testing the flow again.
    func reset() {
        activePlan = nil
        for key in [Keys.activePlan, Keys.lifetimeOfferShown] {
            defaults.removeObject(forKey: key)
        }
    }
}
