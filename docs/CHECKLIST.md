# Launch checklist

The one place that says what is done and what is left. Every other doc explains how something works; none of them keeps its own to-do list. When something here changes, change it here.

Last checked: **2026-11-16** (code, the live site, the n8n waitlist, and a read-through of App Store Connect).

## Before you can press "Add for Review"

These block submission. In order:

- [ ] **1. Upload a build.** TestFlight shows no builds, and the GitHub repository has none of the four secrets the upload needs.
  1. App Store Connect → Users and Access → Integrations → App Store Connect API: create a key with the **App Manager** role. Download the `.p8` (offered once).
  2. GitHub → Settings → Secrets and variables → Actions, add `ASC_KEY_ID`, `ASC_ISSUER_ID` (shown above the keys list), `ASC_KEY_P8` (the whole file's text) and `APPLE_TEAM_ID` (developer.apple.com → Membership).
  3. GitHub → Actions → iOS → **Run workflow**. The TestFlight job archives a Release build, signs it, and uploads it.
  4. On the version page, under **Build**, pick the uploaded build.
- [ ] **2. Upload screenshots.** The "App Previews and Screenshots" tab is empty. Upload the six files in `marketing/aso/screenshots/out/control/en-US/6.3/` to "iPhone with Dynamic Island (medium display)". The app is iPhone-only, so no iPad set is needed.
- [ ] **3. Set price and availability.** Pricing and Availability still says "Add Pricing" and "Set Up Availability". Set the price to Free and choose the countries. Leaving out China mainland avoids the two China notices on the version page; including it means completing them under App Compliance.
- [ ] **4. Finish the three purchases.** The "Pro" group (Weekly, Annual) and "Pro Lifetime" exist. Lifetime shows "Prepare for Submission"; the two subscriptions' statuses were not read. Each needs a price, an English display name and description, and a review screenshot (`docs/APP_STORE.md` → In-app purchases), until its status is **Ready to Submit**. Then, on the version page, add all three under "In-App Purchases and Subscriptions" (the section appears once a build is attached). The first subscription must go in with the app version.
- [ ] **5. Confirm the Privacy Policy URL** under App Privacy is `https://www.simpleshrink.com/privacy`. The two data types are already entered; the URL field was not visible in the check.
- [ ] **6. EU trader status.** Business → Agreements shows "Complete Compliance Requirements" for the Digital Services Act. Declare trader or non-trader, or the app can't be sold in the EU.
- [ ] **7. Test the build from TestFlight on a real iPhone.**
  - [ ] Sign in with a Sandbox account (Users and Access → Sandbox): buy Weekly, buy Annual, buy Lifetime, restore, cancel. Lifetime on top of Weekly must still show Manage Subscription.
  - [ ] Run each cleanup once on the real library: delete, Swipe to clean, burst picks, Live Photos to stills, screenshots, shrink a video, trim a video, one-tap Photo Cleanup, a Files folder.
  - [ ] Compare free space with Settings → General → iPhone Storage before and after.
  - [ ] Try Limited Photos access, an iCloud-only video, and large text on a small iPhone.
  - [ ] Onboarding's "How did you hear about us?": Skip sends nothing; an answer shows up in TelemetryDeck (`docs/ACQUISITION_REPORTING.md`).
- [ ] **8. Press Add for Review.**

## Worth doing first, but not blocking

- [ ] **Release timing.** The version is set to release automatically after approval. Switch to "Manually release" if you want to choose the launch day (and email the waitlist the same day).
- [ ] **Have someone qualified read `/privacy` and `/terms`.** They match the code but aren't legal advice. They name no legal entity and no governing law, on purpose.
- [ ] **Update Next.js.** The site runs 16.4.2; a moderate advisory (GHSA-mfr8-8qww-v76h) is fixed in later versions. The site doesn't use the affected feature combination in any obvious way, but update anyway.
- [ ] **Other App Store localizations.** Only English (U.S.) is filled in. The other 13 names, subtitles and keyword fields are in `marketing/aso/metadata.md` and widen what the US store searches.
- [ ] **Header asset** on the version page (0 of 1). Optional.

## Launch day

- [ ] In Vercel, set `NEXT_PUBLIC_APP_STORE_URL` (and `NEXT_PUBLIC_APP_STORE_PROVIDER_TOKEN` for per-page install attribution), then redeploy. Every waitlist form becomes an App Store button.
- [ ] Set `NEXT_PUBLIC_HIDE_TODO_BANNERS=1` if any owner note still shows on the site.
- [ ] Email the waitlist (the n8n data table `storage_app_waitlist`). Nothing sends this yet; it needs a one-off n8n workflow or an export.
- [ ] Update the carousels' call to action in `marketing/carousels/brand.json`.

## Search (any time)

- [ ] Google Search Console: add `simpleshrink.com` as a Domain property (DNS TXT record), then submit `https://www.simpleshrink.com/sitemap.xml`.
- [ ] Bing Webmaster Tools: import from Search Console, submit the same sitemap.
- [ ] Optional: install [gum](https://github.com/ehmo/gum) and sign in, so SEO runs can read Search Console themselves.
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
