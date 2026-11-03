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

    func testLifetimeOfferShowsOnlyOnce() async {
        let store = await makeStore()
        XCTAssertTrue(store.canShowLifetimeOffer)
        store.markLifetimeOfferShown()
        XCTAssertFalse(store.canShowLifetimeOffer)
    }
}
