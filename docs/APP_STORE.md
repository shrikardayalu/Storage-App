# App Store Connect: what to enter

Everything App Store Connect asks for that the repository can answer,
ready to paste. Steps that need the paid account are in `docs/RELEASE.md`,
and the audit is in `docs/LAUNCH_AUDIT.md`. Test Mode was removed on
2026-11-11: the app scans the whole photo library.

Character limits are checked. The marketing copy (subtitle, promotional
text, description, keywords) is a draft that uses only claims the app and
site already make; edit it freely. The free and Pro lists follow
`CleanupMethod.isPro` in the app (checked 2026-11-14): if that changes,
change the description, the product descriptions, the paywall and `/terms`
with it.

## Before you submit

1. **Deploy the website** (`web/`, see the root `README.md`) with these settings:
   - `NEXT_PUBLIC_SITE_URL`: the real domain.
   - `NEXT_PUBLIC_SUPPORT_EMAIL`: an inbox you read. Until it's set, /support says the inbox isn't open yet, and App Review will likely reject a support page with no way to reach you.
2. **Set `PaywallConfig.siteURL`** in `ios/StorageApp/Purchases/Plans.swift` to the same domain. The paywall, the Lifetime offer and Settings link `/privacy`, `/terms` and `/support` from it.
3. **Have someone qualified read `/privacy` and `/terms`.** They're written to match the code, but they aren't legal advice. Two things they leave out on purpose, because only you can supply them:
   - the legal name of the business or person behind the app;
   - a governing-law clause.

## App information

| Field | Value |
|---|---|
| Name (30) | SimpleShrink: Storage Cleaner (English (U.S.); every localization's name, subtitle and keywords are in `marketing/aso/metadata.md`) |
| Subtitle (30) | Free up space, keep memories |
| Primary category | Utilities |
| Secondary category | Photo & Video |
| Content rights | No third-party content |
| Age rating | 4+. Answer **None** or **No** to every question: no violence, no mature themes, no gambling, no user-generated content, no unrestricted web access. The app opens only Apple's EULA, the site's legal pages, Photos, Settings and WhatsApp. |
| Privacy Policy URL | `https://www.simpleshrink.com/privacy` |
| Support URL | `https://www.simpleshrink.com/support` |
| Marketing URL (optional) | `https://www.simpleshrink.com/` |
| Copyright | `2026 <your legal name>` |
| License Agreement | Apple's standard EULA. The site's `/terms` page applies it and adds to it, so don't upload a custom EULA. |

## App Privacy ("nutrition label")

- **Data collection:** choose **"Yes, we collect data from this app"** for the build with optional onboarding source reporting.
- **Data types (exactly these two; not Device ID):** **Other Data → Other Data Types** (the chosen discovery channel) and **Usage Data → Product Interaction** (survey submission). Purpose: **Analytics**. Both are **not linked to the user's identity** and **not used for tracking**. This is the repository's classification based on Apple's definitions; verify it with the archive's privacy report.
- No Device ID, User ID, email, photos, files or storage readings are sent. The minimal TelemetryDeck client sends the channel and uses one shared sender label, with no per-person ID. Skip sends nothing. Purchases remain with Apple; the website waitlist is separate.
- An ATT prompt is not needed for this survey: it does not link data with other companies for advertising or share with data brokers.
- See [ACQUISITION_REPORTING.md](ACQUISITION_REPORTING.md) for setup, dashboard grouping and limitations. Deploy the updated `/privacy` and `/support` before distributing this build.
- If analytics fields or providers change, update this answer, the manifest and `/privacy` together.

## Export compliance

`ITSAppUsesNonExemptEncryption` is already `false` in `project.yml` and
`xtool-Info.plist`, so App Store Connect won't ask on each build. The app
uses no encryption of its own. SHA-256 is used only to compare files for
duplicates, which is exempt.

## Version information

**Promotional text (170):**

> See what fills your iPhone, then get space back without losing memories: swipe away junk for free, or shrink videos and Live Photos with Pro.

**Description:**

> Your iPhone is full, and you don't want to delete the memories. SimpleShrink finds what's taking the space and lets you decide what to do with each thing.
>
> FREE
> • See your real free space, and what takes it up: photos, videos, Live Photos, screenshots, bursts and big formats.
> • Swipe to clean: extra copies, blurry and black shots, receipts, documents and old screenshots, one at a time, with undo. The best copy of each duplicate stays.
> • Keep the best shot of every burst.
> • Pick what to delete on a review screen. Nothing goes until you confirm.
> • Clean up big files, duplicate copies and old downloads in a folder you pick in Files.
> • Step-by-step guides for space only you can clear: Recently Deleted, WhatsApp, Messages, Safari and unused apps.
> • Measured results: free space is read before and after every cleanup, so you see what really came back.
>
> PRO
> • Shrink 4K videos without deleting them.
> • Trim long recordings to the part you want.
> • Keep Live Photos as stills.
> • Re-save screenshots at a fraction of the size.
> • Clear duplicates, blurry shots and junk in bulk.
> • Clean up all your photos in one tap.
>
> PRIVATE BY DESIGN
> Photos, videos and files are analysed on your iPhone and never uploaded. No account needed. An optional onboarding question shares only how you found us for anonymous channel totals; you can skip it.
>
> SimpleShrink Pro is available as a weekly or annual auto-renewing subscription, or as a one-time Lifetime purchase. Payment is charged to your Apple ID when you confirm. Subscriptions renew automatically unless cancelled at least 24 hours before the end of the current period, and you can manage or cancel them in Settings → your name → Subscriptions.
>
> Terms of Use: https://www.simpleshrink.com/terms
> Privacy Policy: https://www.simpleshrink.com/privacy

**Keywords:** paste each localization's 100-character field from
`marketing/aso/metadata.md`. There are 14 localizations, because the US store
searches ten of them, and each carries a different set of words. They come
from `marketing/aso/metadata.json`, checked by `node marketing/aso/check.mjs`
(limits, repeats, trademarks). See `marketing/aso/README.md`.

**Screenshots:** upload `marketing/aso/screenshots/out/control/en-US/6.3/`
(1206 × 2622). As of 2026-11 App Store Connect's main iPhone slot, "iPhone
with Dynamic Island (medium display)", accepts only 6.1"/6.3" sizes, not
the 6.9" set. Render them
with `node marketing/aso/screenshots/render.mjs --all`; other sets in
`marketing/aso/screenshots/sets/` are for Product Page Optimization tests.
The app screens inside them live in `marketing/app-store/screens/`; replace
those from a 6.9" simulator or device when the app's look changes.

## In-app purchases

| Reference name | Product ID | Type | Price | Display name | Description |
|---|---|---|---|---|---|
| Pro Weekly | `com.simpleshrink.app.pro.weekly` | Auto-renewable, group "Pro", 1 week | $4.99 | Pro Weekly | Shrink videos, Live Photos to stills, one-tap cleanup. |
| Pro Annual | `com.simpleshrink.app.pro.annual` | Auto-renewable, group "Pro", 1 year | $24.99 | Pro Annual | Shrink videos, Live Photos to stills, one-tap cleanup. |
| Pro Lifetime | `com.simpleshrink.app.pro.lifetime` | Non-consumable | $34.99 | Pro Lifetime | Every Pro feature, forever. One payment. |

These match `ios/Products.storekit` and `Plan` in the app. The display names
must stay "Pro Weekly", "Pro Annual" and "Pro Lifetime": the paywall's
disclosure uses those names, and a test checks them against the StoreKit
file.

**Subscription group "Pro":** put **Annual at level 1 and Weekly at level 2**,
as in `Products.storekit`. Each product also needs a **review screenshot** of
the paywall: use `paywall-light.png` from CI's Screenshots artifact. For
Lifetime, take one of Settings → Pro → Get Lifetime, Pay Once.

The first subscription has to be submitted together with an app version.

## App Review notes

Paste this into **App Review Information → Notes**. No sign-in is needed.

> SimpleShrink needs no account.
>
> To review:
>
> 1. Use a device or simulator with some photos and videos in Photos: ideally a duplicate, a Live Photo, a burst, a screenshot and a video longer than a minute.
> 2. Open SimpleShrink, go through onboarding, and allow Full Access to Photos when iOS asks. The scan only reads, and photos and files never leave the device. The last onboarding screen optionally asks how you heard about the app; "Skip for now" sends nothing, and a shared answer sends only that channel to TelemetryDeck for anonymous counts.
> 3. Home shows what the scan found. Swipe to clean, Best shot of each burst and picking items in the Library are free; Shrink videos, Live Photos to stills, Duplicates and junk, Re-save screenshots and one-tap Photo Cleanup are Pro and open the paywall.
>
> Every deletion is reviewed on screen and confirmed by iOS. Photos go to Recently Deleted, and the app then shows how to empty it and measures the space that comes back.
>
> Pro can be bought from the paywall (weekly or annual). Lifetime is at Settings → Pro → Get Lifetime, Pay Once, and is also offered once after closing the paywall. Purchases are restored from the paywall or Settings → Pro → Restore Purchases, and managed from Settings → Pro → Manage Subscription.
>
> Photos access: the app needs Full Access to make changes. With "Limit Access" it shows the picked photos and says that cleanups need full access, with a button to Settings.
>
> The Files cleanup reads only a folder the reviewer picks in the Files picker.

**Contact information:** your name, phone number and email.
