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

Free does it by hand; Pro does the heavy hitters, and does them in one tap.

- **Free:** scan, browse, delete by hand, **Swipe to clean** (likely deletes
  one at a time: extra copies, blurry and black shots, receipts, documents,
  old screenshots; swipe left to delete, right to keep, with undo, and the
  deletes happen together at the end), best shot of each burst, the
  other-app guides (Messages, WhatsApp, offloading, Safari, downloads) and
  folder cleanup in Files.
- **Pro:** shrink and trim videos, Live Photos to stills, re-save screenshots,
  duplicates and junk in bulk, and **one-tap Photo Cleanup** (Live Photos to stills, extra
  copies, and blurry, black and old shots together; receipts and documents
  are left alone).

The split lives in one place, `CleanupMethod.isPro`
(`ios/StorageApp/Purchases/CleanupMethod.swift`); `Plan.proFeatures` lists the
Pro ones on the paywall. The site's pricing page (`web/src/lib/pricing.ts`)
lists the same split.

**When the paywall shows.** Never in onboarding. Onboarding is two screens
(hook, "Sound familiar?"), a live scan that shows where the space went, then
"Which ones do you want to try?" with no PRO tags. The picks are remembered,
and Home's "Your plan" card walks through them in `PlanOrder`: the free fix
that frees the most comes first, but only if it makes a dent (1% of the
album, capped at 250 MB); otherwise Swipe to clean leads. Pro picks follow,
and the paywall opens when one is tapped, with their own number on it. It
also opens once ever, right after the first free cleanup gives space back
("you just freed X. there's Y more waiting for Pro"), and whenever a free
user taps a Pro card on Home. Screenshot re-save (PNG screenshots saved again as smaller HEIC copies)
is a Pro tool and is on the paywall.

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
