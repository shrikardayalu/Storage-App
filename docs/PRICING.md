# Pricing

The pricing page is live at `/pricing`. In the app the paywall is on
(`PaywallConfig.isLaunched = true`) and purchases go through StoreKit 2. Until
the products exist in App Store Connect, Xcode runs use the local store in
`ios/Products.storekit`, and debug builds without any store (xtool installs)
fall back to simulated purchases. Release builds never simulate.

## The model

| Plan     | Price         | Where it appears                                   |
| -------- | ------------- | -------------------------------------------------- |
| Weekly   | $6.99/week    | Main paywall, site                                 |
| Annual   | $39.99/year   | Main paywall (selected by default), site ("save 88%") |
| Lifetime | $49.99 once   | App only: one-time offer after the paywall is closed without buying, shown once ever |

Free: scan, browse, delete, and duplicates and junk. Pro: the shrink tools
(shrink and trim videos, Live Photos to stills, best shot of each burst). The
paywall shows at the end of onboarding, right after the scan reveals what could
be freed, and again when a free user taps a Pro card on Home (they carry a PRO
tag). Screenshot re-save is promised on the site but isn't built, so the app's
paywall doesn't list it.

No free trial, by choice: cleanup is a one-and-done job, so a trial would let
people free their space and cancel without paying. The free scan (which shows
what Pro would save) does the convincing instead. Revisit only if the app adds
ongoing storage management people come back to often.

Prices are placeholders, kept in two places: `web/src/lib/pricing.ts` and
`ios/StorageApp/Purchases/Plans.swift`.

## Where it lives

- Site: `web/src/app/pricing/page.tsx`, linked from the header, footer, and sitemap.
- App: `ios/StorageApp/Purchases/` (`PaywallConfig`, `PurchaseStore`,
  `PaywallFlow`), and onboarding in `ios/StorageApp/Views/Onboarding/`.
  Launch with `-paywallEnabled NO` to try the app with nothing gated.
- Product IDs: `com.example.storageapp.pro.weekly`, `.pro.annual` (one
  subscription group) and `.pro.lifetime` (non-consumable), in `Plan.productID`
  and `ios/Products.storekit`. Change both if the bundle ID changes.

## Testing purchases

- **Unit tests** (`StorageAppTests/PurchaseStoreTests.swift`, run in CI) use
  StoreKit Testing against `Products.storekit`: buying, restoring on a fresh
  install, a cancelled subscription expiring, a refund, and a failed payment.
- **In Xcode**, the scheme runs with `Products.storekit`, so the real purchase
  sheets appear. Debug > StoreKit > Manage Transactions lets you cancel,
  expire or refund and watch Pro switch off.
- **On a phone via xtool** (free Apple ID) there's no store: purchases are
  simulated, and Settings > Pro has **Reset Simulated Purchase**.
- **Sandbox** needs the paid Developer account; see `docs/RELEASE.md`.

## Launch checklist

1. Settle final prices; update `web/src/lib/pricing.ts`, `Plans.swift` and `Products.storekit`.
2. Create the three products in App Store Connect with the IDs above.
3. Point `PaywallConfig.privacyURL` at the live site's `/privacy`.
4. Test buy, restore and cancel with a sandbox account on TestFlight.
