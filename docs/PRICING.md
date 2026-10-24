# Pricing (built, hidden until launch)

Pricing is built on the site and in the app but switched off until the app has
been tested. Purchases in the app are simulated: tapping buy grants the plan
locally, with no StoreKit and no charge.

## The model

| Plan     | Price         | Where it appears                                   |
| -------- | ------------- | -------------------------------------------------- |
| Weekly   | $6.99/week    | Main paywall, site                                 |
| Annual   | $39.99/year   | Main paywall (selected by default), site ("save 89%") |
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

- Site: `web/src/app/pricing/page.tsx`. 404s in production until
  `NEXT_PUBLIC_SHOW_PRICING="true"`, which also adds it to the nav and sitemap.
  `npm run dev` always renders it at `/pricing` with a "preview only" banner.
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
6. Set `PaywallConfig.isLaunched = true` and `NEXT_PUBLIC_SHOW_PRICING="true"`.
7. Update the home page FAQ "Is it free?" answer to mention Pro.
