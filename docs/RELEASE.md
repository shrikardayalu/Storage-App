# Release: TestFlight and the App Store

What's ready in the repo, and the steps only the account holder can do.

## Ready

- Paywall on, StoreKit 2 purchases, restore, Manage Subscription, Terms and
  Privacy links on the paywall (`docs/PRICING.md`).
- Onboarding ending on the paywall (`ios/StorageApp/Views/Onboarding/`).
- No wording claims to clean caches, boost RAM or clear system junk (checked
  2026-11-03 across the app and site; the site only lists those as things no
  app can do).
- A **TestFlight** job in `.github/workflows/ios.yml`. It runs only from
  Actions > iOS > Run workflow, and skips with a warning until the secrets below exist.

## Not done yet

- **Test Mode is still on in every build.** The app reads and changes only the
  "Storage App Test" album, by choice for now. Removing it means widening the
  Photos code past the test album and rewriting `ios/Tools/check-no-device-access.sh`.
- **Bundle ID** is still `com.example.storageapp` (also in `xtool.yml`,
  `Plan.productID`, `Products.storekit`, and the workflow's `BUNDLE_ID`).
- **Photos permission text** in `project.yml` and `xtool-Info.plist` mentions the test album.
- **The legal pages need the real domain and a support email**: `NEXT_PUBLIC_SITE_URL` and
  `NEXT_PUBLIC_SUPPORT_EMAIL` for the site, and `PaywallConfig.siteURL` in the app.
  What to paste into App Store Connect is in `docs/APP_STORE.md`.

## Steps that need the paid Apple Developer account ($99/year)

1. Enroll at developer.apple.com and note your **Team ID** (Membership page).
2. Pick the real bundle ID and replace `com.example.storageapp` everywhere listed above.
3. In App Store Connect: **Apps > +** to create the app with that bundle ID.
4. Under the app's **Subscriptions**, create group "Pro" with Weekly ($6.99, 1 week)
   and Annual ($39.99, 1 year). Under **In-App Purchases**, create Lifetime
   ($49.99, non-consumable). Use the product IDs from `Plan.productID`.
5. **Users and Access > Integrations > App Store Connect API**: create a key
   with the **App Manager** role. Download the `.p8` (only offered once).
6. In GitHub: **Settings > Secrets and variables > Actions**, add:
   - `ASC_KEY_ID`: the key's ID
   - `ASC_ISSUER_ID`: the issuer ID shown above the keys list
   - `ASC_KEY_P8`: the whole `.p8` file's text
   - `APPLE_TEAM_ID`: your Team ID
7. Run **Actions > iOS > Run workflow**. The TestFlight job archives a Release
   build, signs it with cloud-managed certificates, and uploads it.
8. In App Store Connect > TestFlight, add yourself as an internal tester, install
   from the TestFlight app, and sign in with a **Sandbox** account
   (Users and Access > Sandbox) to test buying, restoring and cancelling.
