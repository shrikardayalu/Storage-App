# Launch checklist

The one place that says what is done and what is left. Every other doc explains how something works; none of them keeps its own to-do list. When something here changes, change it here.

Last checked: **2026-11-21** (TestFlight approved for external testers; build 46 waiting on App Store review).

## Before you can press "Add for Review"

These block submission. In order:

- [x] **1. Upload a build.**
  - [x] `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` and `APPLE_TEAM_ID` are GitHub secrets (2026-11-19). The workflow rebuilds the key file from however it was pasted.
  - [x] The TestFlight build uses Xcode 26 (`macos-26` runner) since 2026-11-20: App Store Connect rejects uploads built with an older SDK. From April 2027 it will want Xcode 27.
  - [ ] The simulator app tests still run on Xcode 16 (`macos-15`). On Xcode 26, StoreKit Testing fails to start (`SKInternalErrorDomain` 3) and the purchase tests hang. Get them passing on `macos-26` before GitHub drops Xcode 16 or Apple wants Xcode 27.
  - [x] **Admin key in place** (2026-11-20). The key needs the **Admin** role: with App Manager the archive works but export fails with "Cloud signing permission error", since only Admin may create the cloud-managed distribution certificate. Revoke the first (App Manager) key once a build is up.
  - [x] First build uploaded to App Store Connect (2026-11-20, run 44746667593). New builds: GitHub → Actions → iOS → **Run workflow**.
  - [x] Build 46 (1.0) attached to the version (2026-11-20).
- [x] **2. Screenshots** (seen 2026-11-19): six screenshots and one app preview under "iPhone with Dynamic Island (medium display)". Age rating re-answered for Apple's new Shared Location and Dating questions (No to both, still 4+). The China notices on the version page don't apply, since China mainland is excluded.
- [x] **3. Price and availability** (2026-11-19): Free, 174 countries and regions, everything except China mainland.
- [x] **4. Purchases** (2026-11-20): Weekly ($4.99), Annual ($24.99), Lifetime ($34.99) and the "Pro" group (English name "SimpleShrink Pro") are filled in and sit in the app's **draft submission** as Ready to Submit. There's no purchases section on the version page any more; each item's own "Add for Review" puts it in the draft. The draft goes to Apple only together with the app version (step 7).
- [x] **5. Privacy Policy URL** under App Privacy is `https://www.simpleshrink.com/privacy` (confirmed 2026-11-19).
- [ ] **6. Test the build from TestFlight on a real iPhone.** Build 46 tested 2026-11-20.
  - [x] Purchases (worked 2026-11-20): TestFlight builds use the sandbox with your own Apple ID, and nothing is charged. Buy Weekly, buy Annual, buy Lifetime, restore, cancel. Lifetime on top of Weekly must still show Manage Subscription.
  - [x] Run each cleanup once on the real library (worked 2026-11-20): delete, Swipe to clean, burst picks, Live Photos to stills, screenshots, shrink a video, trim a video, one-tap Photo Cleanup, a Files folder.
  - [x] Compare free space with Settings → General → iPhone Storage before and after.
  - [ ] Try Limited Photos access, an iCloud-only video, and large text on a small iPhone. Not tested yet; you have no iCloud library, so the iCloud-only video is left to the TestFlight friends.
  - Settings → Apple ID → Subscriptions shows SimpleShrink with no icon. That's expected for sandbox purchases before release: the icon comes from the live App Store listing.
  - [ ] Onboarding's "How did you hear about us?": Skip sends nothing; an answer shows up in TelemetryDeck (`docs/ACQUISITION_REPORTING.md`).
- [x] **7. Press Add for Review** (submitted 2026-11-20; waiting on App Review) on the version page, add it to the existing draft submission (which already holds the purchases), then Submit for Review.

## Worth doing first, but not blocking

- [ ] **EU trader status.** Business → Agreements shows "Complete Compliance Requirements" for the Digital Services Act. Until you declare trader or non-trader, the app isn't offered in the 27 EU countries; everywhere else it is. It can be done after launch, and the EU storefronts open once Apple accepts it.
- [x] **TestFlight for friends.** External testing passed Beta App Review (2026-11-21) and the build is going out to testers. Ask them to try Limited Photos access, an iCloud-only video and large text (step 6), and collect what they report.

- [ ] **Release timing.** The version is set to release automatically after approval. Switch to "Manually release" if you want to choose the launch day (and email the waitlist the same day).
- [ ] **Have someone qualified read `/privacy` and `/terms`.** They match the code but aren't legal advice. They name no legal entity and no governing law, on purpose.
- [ ] **Update Next.js.** The site runs 16.4.2; a moderate advisory (GHSA-mfr8-8qww-v76h) is fixed in later versions. The site doesn't use the affected feature combination in any obvious way, but update anyway.
- [ ] **Other App Store localizations.** Only English (U.S.) is filled in. The other 13 names, subtitles and keyword fields are in `marketing/aso/metadata.md` and widen what the US store searches.
- [x] **Header and search results assets** uploaded (2026-11-20): `marketing/aso/creative/out/header.png` (3840 x 1646) and `search.png` (3840 x 2560), rendered by `node marketing/aso/creative/render.mjs` (add `--guides` to see Apple's safe areas). Checked in App Store Connect's Device Preview on iPhone and iPad. They show on iOS 27 and later.

## Launch day

- [ ] In Vercel, set `NEXT_PUBLIC_APP_STORE_URL` (and `NEXT_PUBLIC_APP_STORE_PROVIDER_TOKEN` for per-page install attribution), then redeploy. Every waitlist form becomes an App Store button.
- [ ] Set `NEXT_PUBLIC_HIDE_TODO_BANNERS=1` if any owner note still shows on the site.
- [ ] Email the waitlist (the n8n data table `storage_app_waitlist`). Nothing sends this yet; it needs a one-off n8n workflow or an export.
- [ ] Update the carousels' call to action in `marketing/carousels/brand.json`.

## Search (any time)

- [x] Google Search Console: `simpleshrink.com` added as a property (2026-11-16).
- [x] Sitemap `https://www.simpleshrink.com/sitemap.xml` submitted in Search Console, read with 22 pages (2026-11-19).
- [ ] Bing Webmaster Tools: import from Search Console, submit the same sitemap.
- [x] gum installed in WSL, with `automation/gsc.sh` to call it (2026-11-16).
- [x] Google OAuth client (Desktop app) created and stored in gum, consent screen in production (2026-11-19).
- [x] gum signed in to Search Console with the property owner's account, read-only scope; `gsc.sh sites/query/inspect` verified (2026-11-19).
- Note: "Page with redirect" for `http://` and non-www addresses in Search Console is expected (they 308 to `https://www.`), not an error.
- [ ] In the Claude app, open Scheduled → "SimpleShrink SEO run", confirm the model is Opus 5.5, and press **Run now** once to see a run end to end.

## Done

**Apple account and App Store Connect**

- [x] Enrolled in the Developer Program (2026-11-15). Paid and Free Apps agreements, bank account and W-9 are active.
- [x] App record created: "SimpleShrink: Storage Cleaner", bundle ID `com.simpleshrink.app`, SKU `simpleshrink-ios`, Apple ID 6835211985.
- [x] Subtitle, categories (Utilities, Photo & Video), age rating 4+, content rights, Apple's standard license.
- [x] Promotional text, description, keywords, Support URL, Marketing URL, copyright.
- [x] App Review contact details and notes; no sign-in required.
- [x] App Privacy: Product Interaction and Other Data Types, for Analytics, not linked to identity.
- [x] Subscription group "Pro" with two subscriptions, and the Pro Lifetime purchase, created.

**App**

- [x] Whole-library scan; changes only approved items (Test Mode removed 2026-11-11).
- [x] Paywall on, StoreKit 2 purchases, restore, Manage Subscription, Lifetime in Settings → Pro.
- [x] Terms, Privacy and Support links point at `https://www.simpleshrink.com`.
- [x] Privacy manifest, export-compliance flag, version 1.0.0, iPhone only, iOS 17+.
- [x] No wording claims to clean caches, boost RAM or clear system junk.
- [x] CI green on `main` at `3ebf68e` (2026-11-16): safety check, core tests, build, app tests, unsigned `.ipa`.
- [x] Two code audits (2026-11-04 and 2026-11-14); details in `docs/LAUNCH_AUDIT.md`.

**Website and systems**

- [x] Live at `https://www.simpleshrink.com`. The apex and the old vercel.app address redirect to it.
- [x] `/privacy`, `/terms`, `/support`, `/pricing`, the sitemap, the RSS feed and `/llms.txt` all load; `/support` shows the support email.
- [x] Waitlist works end to end on the live site: form → n8n webhook → data table (tested 2026-11-16, test row removed).
- [x] All six comparison pages are published.
- [x] SEO engine: skill, backlog, log, a build-enforced pace of 5 new guides a week, and a scheduled run four days a week.

## Where things are

| What | Where |
| --- | --- |
| What to paste into App Store Connect | `docs/APP_STORE.md` |
| Prices and the free/Pro split | `docs/PRICING.md` |
| How people found the app (survey) | `docs/ACQUISITION_REPORTING.md` |
| App Store keywords and screenshots | `marketing/aso/README.md` |
| SEO engine | `automation/README.md` |
| How the app was built, step by step (history) | `docs/BUILD_PLAN.md` |
| What the two audits found and fixed (history) | `docs/LAUNCH_AUDIT.md` |
