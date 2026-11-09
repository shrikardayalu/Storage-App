# Pre-launch audit (iOS)

Audit of `ios/` on branch `pre-launch-audit`, started from `main` at `e435ee9`
(2026-11-04). Everything below was checked by reading the code. Builds and
tests were checked by CI (`.github/workflows/ios.yml` on macOS 15), because
this audit ran on Linux without Xcode. The CI results are in
[How this was verified](#how-this-was-verified).

Nothing here changes pricing, product IDs, the bundle ID
(`com.example.storageapp`) or marketing claims.

## Fixed

| What | Where |
|---|---|
| **The app didn't build.** On `main`, `Sketch.arrow` stopped the Swift compiler with "unable to type-check this expression in reasonable time", so every iOS CI run since `127753f` failed at Build. The expression is now split into typed steps. | `ios/StorageApp/Views/Components/Sketch.swift` |
| **No privacy manifest.** Added `PrivacyInfo.xcprivacy` with no tracking, no collected data, and the three required-reason APIs the app uses: UserDefaults (`CA92.1`), disk space (`85F4.1`, shown on Home and used to measure what came back) and file timestamps (`3B52.1`, only for the folder picked in Files). CI now fails if the manifest isn't in the built `.app`, and prints the Photos usage string from the built Info.plist. | `ios/StorageApp/Resources/PrivacyInfo.xcprivacy`, `.github/workflows/ios.yml` |
| **The paywall's subscription disclosure was too thin for Guideline 3.1.2.** It said "$39.99/year, renews automatically. Cancel anytime in Settings." It now names the plan (Pro Weekly or Pro Annual), its price and length, says payment is charged to the Apple ID on confirmation, says it auto-renews unless cancelled at least 24 hours before the period ends, and says where to cancel. | `ios/StorageApp/Purchases/Plans.swift` (`Plan.disclosure`), `PaywallView.swift` |
| **Non-US storefronts showed dollars next to local prices.** The annual row's "Just $0.77/week" and the "save 88%" stamp came from hard-coded US prices, even after the App Store's prices loaded. Both now come from the loaded `Product`s, in the storefront's currency, and fall back to the planned prices only before products load. | `PurchaseStore.annualPerWeek`, `PurchaseStore.annualSavingsPercent`, `PaywallView.swift` |
| **The one-time Lifetime offer had no Restore, Terms or Privacy.** It is a purchase screen of its own, so it now has the same Restore · Terms · Privacy row as the main paywall, and a one-payment disclosure. | `ios/StorageApp/Purchases/PaywallView.swift` |
| **Lifetime bought on top of a subscription hid Manage Subscription.** Lifetime outranks a subscription, and Settings only offered Manage Subscription when the top plan was a subscription. Someone who bought Lifetime while Weekly was active kept paying with no way to cancel from the app. PurchaseStore now tracks any active subscription, and Settings shows the button with a note about what to cancel. | `PurchaseStore.hasActiveSubscription`, `ios/StorageApp/Views/Settings/SettingsView.swift` |
| **Debug builds lost a simulated purchase at launch.** The foreground entitlement refresh could run before `start()` loaded products, and wiped the simulated plan. Release builds never simulate, so this was debug-only. | `PurchaseStore.refreshEntitlements` |
| **Big headlines ignored Dynamic Type.** `Font.display(_:relativeTo:)` took a text style and ignored it, so every display headline (31 call sites) stayed one size at every text setting. It now scales with `UIFontMetrics`, capped at 1.35x so the fixed-height onboarding pages still fit. CI now also takes onboarding, reveal, paywall and Home screenshots at the Accessibility Large text size. | `ios/StorageApp/Views/Components/Sketch.swift`, `.github/workflows/ios.yml` |
| **Stale safety checks.** Burst picks, Live Photos to stills and the video list kept the previous safety check when a new one failed, so they could keep showing items as approved alongside an error. They now clear it, as Duplicates and junk already did. (The model re-checks before any change, so nothing unsafe could have run.) | `BurstPicksView.swift`, `LivePhotoStillsView.swift`, `VideoShrinkView.swift` |
| **The video preview could spin forever.** When Photos returns no player item (an iCloud video while offline, say), the video screen showed a spinner forever. It now says the preview isn't available; shrinking still works. | `ios/StorageApp/Views/Cleanup/VideoShrinkView.swift` (`TrimPlayer.couldNotLoad`) |
| **"Open Photos" in the Recently Deleted guide could be a dead button.** If iOS refused `photos-redirect://`, nothing happened. It now shows an alert that says to open Photos from the Home Screen, as the other-app guides already did. | `ios/StorageApp/Views/Cleanup/RecentlyDeletedGuideView.swift` |
| **No privacy policy or terms outside the paywall.** Settings > About now links Privacy Policy and Terms of Use. | `ios/StorageApp/Views/Settings/SettingsView.swift` |

Tests added for the logic above:

- `StorageAppTests/PurchaseStoreTests.swift` gets 8 new tests:
  - storefront per-week and savings figures, and the fallback before products load
  - `Plan.savingsPercent` edge cases
  - the disclosure text for each plan
  - store names matching `Products.storekit`
  - Lifetime alone having no subscription to manage
  - a simulated plan surviving an early refresh, and the real store replacing a simulated plan

  It also extends 2 existing tests to check `hasActiveSubscription`: Lifetime bought on top of Weekly, and a subscription expiring.
- Two existing tests, `testCancelledSubscriptionEndsProWhenItExpires` and `testRefundEndsProAtOnce`, had never run, because main stopped at the build error. Once the build worked they failed on CI: they read entitlements once, straight after `SKTestSession` expired or refunded, and StoreKit Testing applies those changes asynchronously. They now re-read until Pro is gone, up to 15 seconds, and still fail if it never goes. The app itself re-reads on every `Transaction.updates` event and every return to the foreground, so it doesn't depend on a single read.
- `StorageAppTests/DynamicTypeTests.swift` (new) adds 5 tests: the default size, growth, shrinking, the cap, and the text-style mapping.

### Checked and fine

- **StoreKit matches `Products.storekit`.** `Plan.productID` gives `com.example.storageapp.pro.weekly`, `.annual` and `.lifetime`. These match the file's two auto-renewing subscriptions (one group, "Pro", P1W and P1Y) and the non-consumable. The prices in `Plan.price` ($6.99, $39.99, $49.99) match `displayPrice` there. The scheme runs with that file, and `SKTestSession` in the tests reads it.
- **Entitlements** come from `Transaction.currentEntitlements`, read at launch, on every return to the foreground, after each purchase, and on `Transaction.updates`. Revoked (refunded) and expired transactions are skipped, and unverified ones are ignored.
- **Restore** is on the paywall, on the Lifetime offer (new) and in Settings, and it calls `AppStore.sync()`.
- **Gating**: the three Pro tools (Live Photos to stills, video shrink, burst picks) are reachable only through `CleanupSection.proLink`, which opens the paywall when `requiresPro` is true. Deleting, duplicates and junk, Files and the guides stay free, as the paywall says.
- **Test Mode** (`-paywallEnabled NO`) and simulated purchases are debug-only, or launch-argument-only, which can't be set on a store install.
- `ios/Tools/check-no-device-access.sh` passes. CI runs it first, and I ran it locally after every change. It caught one problem: the manifest's own comment mentioned the network API it greps for, and the comment is now reworded.
- **Force-unwraps.** The two in `JunkFinder.duplicateGroups` index into a dictionary the same function just filtered to non-empty entries, and the `URL(string:)!` literals are constant. No `try!` or `as!`.
- **No TODOs or placeholder copy** in the app. The only "placeholder" matches are PhotoKit's `PHObjectPlaceholder`.
- **App icon**: a single 1024x1024 RGB PNG with no alpha channel, which is what Xcode 15+ expects. **Launch screen**: `UILaunchScreen` with a light and dark `LaunchBackground` color. **Dark mode**: every theme color has a dark value, and CI screenshots every route in both appearances. **Encryption**: `ITSAppUsesNonExemptEncryption` is `false`.
- **Accessibility**: icon-only buttons (close, ×) have labels, illustrations are hidden from VoiceOver, and cards combine into one element with a spoken size.
- **No wording claims to clean caches, boost RAM or clear system junk.** The only "cache" mentions are Safari's own data and iOS clearing caches by itself.

### Every flow, traced

From `StorageApp.swift`, `RootView` shows the tabs (Home, Library, Settings), with onboarding on top until it's finished. It also shows the two full-screen guides and one error alert.

- **Onboarding** (reworked 2026-11-05): hook, pain (which explains the Photos permission in a footnote), scan (ends on "Videos take N% of it" and "Show me what to do"), then "Which ones do you want to try?", which finishes onboarding. No paywall in onboarding. Back works on pain. The scan has a state for each outcome, and each offers "Continue without a scan", which finishes onboarding:
  - Access denied: Open Settings, then rescan automatically on return.
  - The album is missing or there are two: Scan again.
  - The album is empty.

  Home then shows "Your plan" with the picks until it's closed. The paywall opens from a Pro pick or card, and once after the first free cleanup; its ✕ leads to the Lifetime offer once. No dead ends.
- **Home**: the storage card (loading, failed and loaded states), Results, the test-album card (scan, scan again, error with Open Settings), "space waiting in Recently Deleted" (reopens the last guide), Clean up (shown only once a scan has items), Files, Other apps guides, and Results again.
- **Junk review**: shows progress while analysing, then either "Nothing to clean" or the review. The review has a safety check, a confirm step, removal, and then the Recently Deleted guide. When a copy is also in another album, it's shown as blocked.
- **Burst picks, Live Photos to stills, video shrink**: each has an empty state, a per-item blocked state, an error line, a confirm step and the guide afterwards. The video screen makes a copy before anything changes, and throws the copy away when you leave the screen.
- **Pick to delete** (Library select): a review sheet with a receipt you can edit, a safety-check stamp, the confirm step, and the guide once the sheet closes.
- **Files**: pick, scan, review, delete for good, then the before and after figures. Each file is in only one of the duplicates, large and old lists, and the model refuses a removal that would take every copy.
- **Recently Deleted guide** and **other-app guides**: a full-screen cover with ✕ on every page. Returning from the other app measures again. The last page has Done or "Close for Now".
- **Results**: two entry points, pull to refresh, and "Start Counting Again" with a confirmation.
- **Settings**: Photos access, with "Change Selected Photos" and "Change Access in Settings" when access is limited or denied. Also the guide toggle, Pro (Upgrade, Restore, Manage Subscription), debug readings, version, and Privacy and Terms links (new).

## Needs my decision

1. **Test Mode: decided, it stays on for now.** The app reads and changes only the "Storage App Test" album. App Review may still reject a Test Mode build under 2.1. `docs/APP_STORE.md` has review notes that tell the reviewer how to create the album, which gives it the best chance. If it is rejected, the fix is to widen the Photos code to the whole library behind the same review screens.
2. **Privacy policy: done.** It needs your domain and an email address. `/privacy` now covers the app, and new `/terms` and `/support` pages exist on the site (see Added after the audit, below). Still needed from you:
   - the real domain, in `NEXT_PUBLIC_SITE_URL` and `PaywallConfig.siteURL`;
   - a support inbox, in `NEXT_PUBLIC_SUPPORT_EMAIL`;
   - your legal name, for the copyright line;
   - a reading of both pages by someone qualified.
3. **Terms: done.** The site's `/terms` applies Apple's Standard EULA and adds the app's own terms. Leave the License Agreement in App Store Connect as Apple's standard one. The terms don't name a governing law, because that depends on where you or your business are. A lawyer can add it.
4. **Done (2026-11-05): the ✕ now appears after 0.5 seconds.** Was: **the paywall's ✕ appears after 1.6 seconds.** It's tappable while invisible, so nobody is trapped, but reviewers sometimes flag a delayed close.
   - Options: keep it; shorten it to about 0.5 seconds; or show it immediately.
   - **Recommendation: shorten it to about 0.5 seconds.**
5. **Done (2026-11-05): the app labels and "now" are gone; the messages stay.** Was: **the pain screen draws iOS-style system alerts** ("SETTINGS · iPhone Storage Full", "SOFTWARE UPDATE · Unable to Download Update"). They're drawn on paper and clearly illustrations, but Apple dislikes UI that imitates system alerts. This is marketing copy, so I left it alone.
   - Options: keep it; or drop the Apple app labels (SETTINGS, CAMERA, SOFTWARE UPDATE) and keep the messages.
   - **Recommendation: drop the labels.**
6. **The Lifetime offer is shown once, ever.** "You won't see this offer again" is true in code, because there's no other way to buy Lifetime. That also means someone who wants it later can't buy it.
   - Options: keep it; or also list Lifetime in Settings > Pro.
   - **Recommendation: keep it as designed, but know that it closes that sale for good.** It's a pricing decision, so I didn't change it.
7. **The "save 88%" stamp compares Annual with 52 weeks of Weekly.** That's arithmetically true, and it now uses storefront prices, but it's a large marketing claim.
   - **Recommendation: keep it.** It's honest, and common in this category.
8. **`photos-redirect://` isn't a documented URL scheme** (Guideline 2.5.1, public APIs). Many apps use it, and the button now falls back to an alert.
   - **Recommendation: keep it.** If review objects, drop the button and keep the written steps.
9. **The display name is "SimpleShrink" (decided 2026-11-06); the bundle ID `com.example.storageapp` is still a placeholder** in `docs/RELEASE.md`. Decide it before the App Store Connect record is created, because product IDs derive from the bundle ID.

## Added after the audit

| What | Where |
|---|---|
| **Privacy Policy** covering the app and the site. The app collects no data: photos and the picked Files folder are analysed on the iPhone, and readings and settings stay on the device. Purchases are handled by Apple. | `web/src/app/privacy/page.tsx` |
| **Terms of Use**: Apple's Standard EULA plus the app's own terms. They cover approving deletions, Files deletions being permanent, the auto-renewal and Lifetime terms the paywall shows, refunds through Apple, the limits on liability, and the Apple clause. | `web/src/app/terms/page.tsx` |
| **Support page** (the App Store Connect Support URL): restore, cancel, Lifetime on top of a subscription, refunds, Photos access in Test Mode, Recently Deleted, and privacy. It has an email contact once `NEXT_PUBLIC_SUPPORT_EMAIL` is set. | `web/src/app/support/page.tsx`, `web/src/lib/site.ts` |
| **The app links all three from one `PaywallConfig.siteURL`.** Terms now point at the site's `/terms`, and Settings gains Support. A test checks the URLs. | `ios/StorageApp/Purchases/Plans.swift`, `SettingsView.swift` |
| **App Store Connect copy and answers**: subtitle, description, keywords, category, age rating, App Privacy, export compliance, IAP metadata, subscription levels, and App Review notes for Test Mode. | `docs/APP_STORE.md` |

## Needs a paid Apple account or a real device

- Enrol, pick the real bundle ID, and create the App Store Connect record. Create the "Pro" subscription group (Weekly, Annual) and the Lifetime IAP with the IDs from `Plan.productID`, then sign the Paid Apps agreement and add tax and banking. Until products are "Ready to Submit", a TestFlight build can't load them: release builds then say the store isn't available, and debug builds simulate.
- **Sandbox and TestFlight purchases on a device**: buy, cancel, renew (sandbox runs time faster), Ask to Buy (pending), refund, and restore on a second device. Also check that Lifetime on top of Weekly shows Manage Subscription (fixed above).
- **App Privacy in App Store Connect**: "Data Not Collected", which matches the manifest (see `docs/APP_STORE.md`). After archiving, check Xcode's privacy report, which merges any SDK manifests (the app has no third-party SDKs today).
- **App Store screenshots** at the sizes App Store Connect asks for (6.9" and 6.5" iPhone). CI's simulator screenshots are a 6.3" iPhone Pro and aren't store-ready.
- **On a real phone**, check what the simulator can't:
  - iOS's own delete prompt, limited Photos access, and iCloud-only videos (now with the "can't preview" state).
  - Live Photo to still conversion keeping its details, and burst cleanup.
  - Free-space readings against Settings.
  - `photos-redirect://` and `whatsapp://` opening.
  - Large text on a small phone (iPhone SE and mini), where the fixed-height onboarding pages are tightest.
- **Age rating, review notes, and a demo path for the reviewer**: drafted in `docs/APP_STORE.md`, ready to paste once the record exists.

## How this was verified

GitHub Actions, workflow **iOS**, run
[41746376782](https://github.com/shrikardayalu/Storage-App/actions/runs/41746376782)
on `pre-launch-audit`, passed:

| Job | Result |
|---|---|
| Safety check (`check-no-device-access.sh`) and `swift test` | Passed: 112 StorageCore tests, 0 failures |
| Build for the simulator | Passed |
| Check the app bundle (new) | Passed: `PrivacyInfo.xcprivacy` is in the `.app` and lints, and the Photos usage string is present |
| Screenshots: 9 routes in light and dark, plus 4 at Accessibility Large text (new) | Taken and uploaded as the **Screenshots** artifact |
| App tests (`xcodebuild test-without-building`) | Passed: 58 tests, 0 failures, including StoreKit Testing purchases, restore, expiry and refund |
| Unsigned Release `.ipa` for the device | Passed |
| TestFlight | Skipped (manual only, and needs the secrets in `docs/RELEASE.md`) |

Before this branch, every iOS run on `main` since `127753f` failed at Build
(see the first Fixed item).

**What I couldn't check from here:** I can read Actions results with `gh`,
but this environment's network policy blocks downloading artifacts, so I
haven't looked at the screenshots myself. Please open the **Screenshots**
artifact on the run above, especially the four `*-largetext.png` files, to
confirm the onboarding, reveal and paywall pages still fit at large text
sizes, and check the dark-mode shots. Nothing ran on a real device.
