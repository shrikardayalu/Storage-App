# Pricing

The pricing page is live at `/pricing`. Purchases in the app are still
simulated: tapping buy grants the plan locally, with no StoreKit and no charge.
The in-app paywall stays off until `PaywallConfig.isLaunched` is turned on.

## The model

| Plan     | Price         | Where it appears                                   |
| -------- | ------------- | -------------------------------------------------- |
| Weekly   | $6.99/week    | Main paywall, site                                 |
| Annual   | $39.99/year   | Main paywall (selected by default), site ("save 88%") |
| Lifetime | $49.99 once   | App only: one-time offer after the paywall is closed without buying, shown once ever |

Free: scan, browse, and delete. Pro: the shrink tools (compress, trim, Live
Photos to stills, screenshot re-save, burst picks). In the app the paywall
opens when a free user taps **Compress** in Review Cleanup; deleting stays free.

No free trial, by choice: cleanup is a one-and-done job, so a trial would let
people free their space and cancel without paying. The free scan (which shows
what Pro would save) does the convincing instead. Revisit only if the app adds
ongoing storage management people come back to often.

Prices are placeholders, kept in two places: `web/src/lib/pricing.ts` and
`ios/StorageApp/Purchases/Plans.swift`.

## Where it lives

- Site: `web/src/app/pricing/page.tsx`, linked from the header, footer, and sitemap.
- App: `ios/StorageApp/Purchases/` (`PaywallConfig`, `PurchaseStore`,
  `PaywallFlow`). Off while `PaywallConfig.isLaunched` is `false`. To try it on
  a test build, launch with `-paywallEnabled YES`; Settings then shows a Pro
  section with **Upgrade to Pro** and **Reset Simulated Purchase**.

## Launch checklist

1. Settle final prices; update both files above.
2. Create the three products in App Store Connect (two auto-renewing
   subscriptions in one group, plus one non-consumable for lifetime).
3. Replace `PurchaseStore.purchase(_:)` and `restore()` with StoreKit 2, and
   show `Product.displayPrice` instead of the hard-coded prices.
4. Add Terms of Use and Privacy links to the paywall (App Review requires them
   for subscriptions).
5. Remove **Reset Simulated Purchase** from Settings.
6. Set `PaywallConfig.isLaunched = true`.
