import Foundation
import Observation
import StoreKit

/// Who has Pro, backed by StoreKit 2.
///
/// Pro comes from the App Store's own record of what this Apple ID owns
/// (`Transaction.currentEntitlements`), checked at launch, each time the app
/// comes back to the foreground, and whenever a transaction arrives. A
/// cancelled subscription keeps Pro until its period ends, then drops out of
/// the entitlements on its own; a refund drops it at once.
///
/// Builds without App Store products (an xtool install on a free Apple ID, or
/// a simulator run without `Products.storekit`) can't load prices. Debug
/// builds then fall back to simulated purchases, so the flow can still be
/// tried on a phone; release builds say the store isn't available.
@MainActor
@Observable
final class PurchaseStore {
    enum Outcome: Equatable {
        case purchased
        case cancelled
        /// Waiting on Ask to Buy or a payment check. Pro arrives through `Transaction.updates`.
        case pending
        case failed(String)
    }

    private(set) var activePlan: Plan?
    /// A weekly or annual subscription is active, even if Lifetime outranks it.
    /// Someone who bought Lifetime on top still pays for this until they cancel it.
    private(set) var hasActiveSubscription = false
    private(set) var isPurchasing = false
    /// Products from the App Store, once loaded.
    private(set) var products: [Plan: Product] = [:]
    /// True after a load attempt came back without products.
    private(set) var storeUnavailable = false

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let allowsSimulation: Bool
    @ObservationIgnored private var updates: Task<Void, Never>?

    private enum Keys {
        static let simulatedPlan = "purchases.activePlan"
        static let lifetimeOfferShown = "purchases.lifetimeOfferShown"
    }

    init(defaults: UserDefaults = .standard, allowsSimulation: Bool = PaywallConfig.allowsSimulatedPurchases) {
        self.defaults = defaults
        self.allowsSimulation = allowsSimulation
        if allowsSimulation {
            activePlan = defaults.string(forKey: Keys.simulatedPlan).flatMap(Plan.init(rawValue:))
        }
    }

    var isPro: Bool { activePlan != nil }

    /// True when a Pro feature should open the paywall instead of running.
    var requiresPro: Bool { PaywallConfig.isEnabled && !isPro }

    /// Purchases are simulated because the App Store has no products for this build.
    var isSimulated: Bool { allowsSimulation && storeUnavailable }

    /// The lifetime deal is a one-time offer: shown after the first paywall
    /// dismissal, then never again.
    var canShowLifetimeOffer: Bool {
        !isPro && !defaults.bool(forKey: Keys.lifetimeOfferShown)
    }

    func markLifetimeOfferShown() {
        defaults.set(true, forKey: Keys.lifetimeOfferShown)
    }

    /// The App Store's localized price, or the planned US price before products load.
    func displayPrice(_ plan: Plan) -> String {
        products[plan]?.displayPrice ?? plan.displayPrice
    }

    /// The annual price spread over a week, in the storefront's currency once
    /// products load, so it never shows dollars next to a local price.
    var annualPerWeek: String {
        guard let annual = products[.annual] else { return Plan.annualPerWeek }
        return (annual.price / 52).formatted(annual.priceFormatStyle)
    }

    /// Annual's saving against a year of weekly, from the storefront's own prices.
    var annualSavingsPercent: Int {
        guard let annual = products[.annual], let weekly = products[.weekly] else { return Plan.annualSavingsPercent }
        return Plan.savingsPercent(annual: annual.price, weekly: weekly.price)
    }

    /// The purchase disclosure for `plan`, with the storefront's price.
    func disclosure(_ plan: Plan) -> String {
        plan.disclosure(price: displayPrice(plan))
    }

    // MARK: Store

    /// Loads products, reads what's owned, and starts listening for
    /// transactions made elsewhere (another device, Ask to Buy, a renewal).
    func start() async {
        if updates == nil {
            updates = Task { [weak self] in
                for await result in Transaction.updates {
                    guard let self else { return }
                    if case .verified(let transaction) = result {
                        await transaction.finish()
                    }
                    await self.refreshEntitlements()
                }
            }
        }
        await loadProducts()
        await refreshEntitlements()
    }

    func loadProducts() async {
        do {
            let loaded = try await Product.products(for: Plan.allCases.map(\.productID))
            products = Dictionary(uniqueKeysWithValues: loaded.compactMap { product in
                Plan(productID: product.id).map { ($0, product) }
            })
        } catch {
            products = [:]
        }
        storeUnavailable = products.isEmpty
    }

    /// Reads what this Apple ID owns right now. Lifetime beats annual beats weekly.
    func refreshEntitlements() async {
        // Debug builds can't tell a simulated plan from a real one until the
        // products load (or fail to). Without this, the foreground refresh at
        // launch, which can run before `start()` loads products, wiped a
        // simulated plan. Release builds never simulate, so this never skips there.
        if allowsSimulation && products.isEmpty { return }
        var owned: Set<Plan> = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.revocationDate == nil,
                  let plan = Plan(productID: transaction.productID)
            else { continue }
            if let expiry = transaction.expirationDate, expiry < Date() { continue }
            owned.insert(plan)
        }
        activePlan = [Plan.lifetime, .annual, .weekly].first(where: owned.contains)
        hasActiveSubscription = owned.contains(where: \.isSubscription)
    }

    func purchase(_ plan: Plan) async -> Outcome {
        isPurchasing = true
        defer { isPurchasing = false }

        if products.isEmpty { await loadProducts() }
        guard let product = products[plan] else {
            if allowsSimulation { return await simulatePurchase(plan) }
            return .failed("The App Store isn't available right now. Please try again in a moment.")
        }

        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    return .failed("The App Store couldn't verify this purchase. Try Restore Purchases.")
                }
                await transaction.finish()
                await refreshEntitlements()
                return isPro ? .purchased : .failed("The purchase went through but Pro isn't active yet. Try Restore Purchases.")
            case .pending:
                return .pending
            case .userCancelled:
                return .cancelled
            @unknown default:
                return .cancelled
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Asks the App Store for this Apple ID's purchases. Returns whether Pro is active.
    func restore() async -> Bool {
        isPurchasing = true
        defer { isPurchasing = false }
        if isSimulated { return isPro }
        try? await AppStore.sync()
        await refreshEntitlements()
        return isPro
    }

    // MARK: Simulation (debug builds without App Store products)

    private func simulatePurchase(_ plan: Plan) async -> Outcome {
        try? await Task.sleep(for: .milliseconds(700))
        activePlan = plan
        defaults.set(plan.rawValue, forKey: Keys.simulatedPlan)
        return .purchased
    }

    /// Clears a simulated plan and the one-time offer, for trying the flow again.
    func resetSimulation() {
        activePlan = isSimulated ? nil : activePlan
        for key in [Keys.simulatedPlan, Keys.lifetimeOfferShown] {
            defaults.removeObject(forKey: key)
        }
    }
}
