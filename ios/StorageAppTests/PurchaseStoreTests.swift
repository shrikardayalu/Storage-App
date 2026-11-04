import StoreKit
import StoreKitTest
import XCTest
@testable import StorageApp

/// Buying, restoring, cancelling and refunds (Build Plan step 12), run against
/// a local App Store built from `Products.storekit`. No Apple account needed.
@MainActor
final class PurchaseStoreTests: XCTestCase {
    private var session: SKTestSession!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        session = try SKTestSession(configurationFileNamed: "Products")
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        defaults = UserDefaults(suiteName: "PurchaseStoreTests")
        defaults.removePersistentDomain(forName: "PurchaseStoreTests")
    }

    override func tearDown() async throws {
        session.clearTransactions()
        session = nil
    }

    private func makeStore() async -> PurchaseStore {
        let store = PurchaseStore(defaults: defaults, allowsSimulation: false)
        await store.start()
        return store
    }

    func testLoadsAllThreeProductsWithStorePrices() async {
        let store = await makeStore()
        XCTAssertEqual(Set(store.products.keys), Set(Plan.allCases))
        XCTAssertFalse(store.storeUnavailable)
        XCTAssertFalse(store.isSimulated)
        XCTAssertEqual(store.displayPrice(.annual), store.products[.annual]?.displayPrice)
    }

    func testStartsFree() async {
        let store = await makeStore()
        XCTAssertFalse(store.isPro)
        XCTAssertTrue(store.requiresPro || !PaywallConfig.isEnabled)
    }

    func testBuyingAnnualGivesPro() async {
        let store = await makeStore()
        let outcome = await store.purchase(.annual)
        XCTAssertEqual(outcome, .purchased)
        XCTAssertEqual(store.activePlan, .annual)
        XCTAssertFalse(store.requiresPro)
    }

    func testBuyingLifetimeGivesPro() async {
        let store = await makeStore()
        let outcome = await store.purchase(.lifetime)
        XCTAssertEqual(outcome, .purchased)
        XCTAssertEqual(store.activePlan, .lifetime)
    }

    func testLifetimeWinsOverASubscription() async {
        let store = await makeStore()
        _ = await store.purchase(.weekly)
        _ = await store.purchase(.lifetime)
        XCTAssertEqual(store.activePlan, .lifetime)
    }

    func testRestoreFindsAnEarlierPurchaseOnAFreshInstall() async {
        let first = await makeStore()
        _ = await first.purchase(.weekly)

        // A new store reads the App Store's record, not anything saved locally.
        let reinstalled = await makeStore()
        XCTAssertEqual(reinstalled.activePlan, .weekly)
        let restored = await reinstalled.restore()
        XCTAssertTrue(restored)
    }

    func testRestoreWithNothingBoughtStaysFree() async {
        let store = await makeStore()
        let restored = await store.restore()
        XCTAssertFalse(restored)
        XCTAssertFalse(store.isPro)
    }

    func testCancelledSubscriptionEndsProWhenItExpires() async throws {
        let store = await makeStore()
        _ = await store.purchase(.annual)
        XCTAssertTrue(store.isPro)

        try session.expireSubscription(productIdentifier: Plan.annual.productID)
        await store.refreshEntitlements()
        XCTAssertFalse(store.isPro)
    }

    func testRefundEndsProAtOnce() async throws {
        let store = await makeStore()
        _ = await store.purchase(.lifetime)
        let transaction = try XCTUnwrap(session.allTransactions().first)

        try session.refundTransaction(identifier: transaction.identifier)
        await store.refreshEntitlements()
        XCTAssertFalse(store.isPro)
    }

    func testFailedPaymentLeavesFree() async {
        let store = await makeStore()
        session.failTransactionsEnabled = true
        let outcome = await store.purchase(.annual)
        if case .failed = outcome {} else { XCTFail("Expected a failure, got \(outcome)") }
        XCTAssertFalse(store.isPro)
    }

    // MARK: Paywall copy (Guideline 3.1.2)

    func testPerWeekAndSavingsUseTheStorefrontsPrices() async throws {
        let store = await makeStore()
        let annual = try XCTUnwrap(store.products[.annual])
        let weekly = try XCTUnwrap(store.products[.weekly])
        XCTAssertEqual(store.annualPerWeek, (annual.price / 52).formatted(annual.priceFormatStyle))
        XCTAssertEqual(store.annualSavingsPercent, Plan.savingsPercent(annual: annual.price, weekly: weekly.price))
    }

    func testPerWeekAndSavingsFallBackBeforeProductsLoad() {
        let store = PurchaseStore(defaults: defaults, allowsSimulation: false)
        XCTAssertEqual(store.annualPerWeek, Plan.annualPerWeek)
        XCTAssertEqual(store.annualSavingsPercent, Plan.annualSavingsPercent)
    }

    func testSavingsPercent() {
        // $39.99 a year against 52 x $6.99 = $363.48.
        XCTAssertEqual(Plan.savingsPercent(annual: 39.99, weekly: 6.99), 88)
        XCTAssertEqual(Plan.savingsPercent(annual: 52, weekly: 1), 0)
        XCTAssertEqual(Plan.savingsPercent(annual: 100, weekly: 1), 0, "Never a negative saving")
        XCTAssertEqual(Plan.savingsPercent(annual: 10, weekly: 0), 0)
    }

    func testSubscriptionDisclosureSaysPriceLengthAndRenewal() async {
        let store = await makeStore()
        for plan in [Plan.weekly, .annual] {
            let text = store.disclosure(plan)
            XCTAssertTrue(text.contains(plan.storeName), text)
            XCTAssertTrue(text.contains(store.displayPrice(plan)), text)
            XCTAssertTrue(text.contains(plan == .weekly ? "per week" : "per year"), text)
            XCTAssertTrue(text.contains("renews automatically"), text)
            XCTAssertTrue(text.contains("24 hours"), text)
            XCTAssertTrue(text.contains("Apple ID"), text)
        }
        let lifetime = store.disclosure(.lifetime)
        XCTAssertTrue(lifetime.contains(store.displayPrice(.lifetime)), lifetime)
        XCTAssertFalse(lifetime.contains("renews automatically"), lifetime)
    }

    func testStoreNamesMatchTheStoreKitConfiguration() async throws {
        let store = await makeStore()
        for plan in Plan.allCases {
            XCTAssertEqual(try XCTUnwrap(store.products[plan]).displayName, plan.storeName)
        }
    }

    // MARK: Simulated purchases (debug builds without App Store products)

    func testSimulatedPlanSurvivesARefreshBeforeProductsLoad() async {
        defaults.set(Plan.annual.rawValue, forKey: "purchases.activePlan")
        let store = PurchaseStore(defaults: defaults, allowsSimulation: true)
        XCTAssertEqual(store.activePlan, .annual)
        // The foreground refresh can run before `start()` has loaded products.
        await store.refreshEntitlements()
        XCTAssertEqual(store.activePlan, .annual)
    }

    func testRealStoreReplacesASimulatedPlanOnceProductsLoad() async {
        defaults.set(Plan.annual.rawValue, forKey: "purchases.activePlan")
        let store = PurchaseStore(defaults: defaults, allowsSimulation: true)
        await store.start()
        XCTAssertFalse(store.isSimulated)
        XCTAssertNil(store.activePlan, "The App Store's record wins once it's reachable")
    }

    func testLifetimeOfferShowsOnlyOnce() async {
        let store = await makeStore()
        XCTAssertTrue(store.canShowLifetimeOffer)
        store.markLifetimeOfferShown()
        XCTAssertFalse(store.canShowLifetimeOffer)
    }
}
