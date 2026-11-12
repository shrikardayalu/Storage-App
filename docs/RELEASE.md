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

- **Test Mode is off (2026-11-11).** The app scans the whole photo library
  (or just the picked photos with limited access) and changes only the items
  approved on a review screen. `ios/Tools/check-no-device-access.sh` now
  checks that every change looks its items up by approved ID behind the
  safety gate, and fails if the test album comes back.

## Not done yet

- **A run on a big real library.** The whole-library code is built and unit
  tested, and installed on a phone, but each cleanup (delete, Live Photos to
  stills, bursts, screenshots, videos) still needs one pass by hand on a real
  library before release. The first scan measures every photo for duplicates
  and blur; that takes minutes on a large library, runs in the background and
  is saved, so it happens once.
- **The legal pages need the real domain and a support email**: `NEXT_PUBLIC_SITE_URL` and
  `NEXT_PUBLIC_SUPPORT_EMAIL` for the site, and `PaywallConfig.siteURL` in the app.
  What to paste into App Store Connect is in `docs/APP_STORE.md`.

## Steps that need the paid Apple Developer account ($99/year)

1. Enroll at developer.apple.com and note your **Team ID** (Membership page).
2. Register the bundle ID `com.simpleshrink.app` (set 2026-11-09 in `project.yml`, `xtool.yml`,
   `Plan.productID`, `Products.storekit` and the workflow's `BUNDLE_ID`).
3. In App Store Connect: **Apps > +** to create the app with that bundle ID.
4. Under the app's **Subscriptions**, create group "Pro" with Weekly ($4.99, 1 week)
   and Annual ($24.99, 1 year). Under **In-App Purchases**, create Lifetime
   ($34.99, non-consumable). Use the product IDs from `Plan.productID`.
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
