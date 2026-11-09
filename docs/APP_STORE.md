# App Store Connect: what to enter

Everything App Store Connect asks for that the repository can answer,
ready to paste. Steps that need the paid account are in `docs/RELEASE.md`,
and the audit is in `docs/LAUNCH_AUDIT.md`. Test Mode stays on for now, so
the review notes below tell the reviewer how to set up the test album.

Character limits are checked. The marketing copy (subtitle, promotional
text, description, keywords) is a draft that uses only claims the app and
site already make; edit it freely.

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
| Name (30) | SimpleShrink |
| Subtitle (30) | Free up space, keep memories |
| Primary category | Utilities |
| Secondary category | Photo & Video |
| Content rights | No third-party content |
| Age rating | 4+. Answer **None** or **No** to every question: no violence, no mature themes, no gambling, no user-generated content, no unrestricted web access. The app opens only Apple's EULA, the site's legal pages, Photos, Settings and WhatsApp. |
| Privacy Policy URL | `https://<your domain>/privacy` |
| Support URL | `https://<your domain>/support` |
| Marketing URL (optional) | `https://<your domain>/` |
| Copyright | `2026 <your legal name>` |
| License Agreement | Apple's standard EULA. The site's `/terms` page applies it and adds to it, so don't upload a custom EULA. |

## App Privacy ("nutrition label")

- **Data collection:** choose **"No, we do not collect data from this app"**. That gives **Data Not Collected**, which matches `PrivacyInfo.xcprivacy`.
- **Why that's true:**
  - The app has no networking. `ios/Tools/check-no-device-access.sh` fails CI if any appears.
  - Photos and files are analysed on the device.
  - Purchases go through Apple.
  - The waitlist email belongs to the website, not the app, so it doesn't count here.
- **If the app ever adds analytics, crash reporting or any server call,** update this answer, the manifest and `/privacy` together.

## Export compliance

`ITSAppUsesNonExemptEncryption` is already `false` in `project.yml` and
`xtool-Info.plist`, so App Store Connect won't ask on each build. The app
uses no encryption of its own. SHA-256 is used only to compare files for
duplicates, which is exempt.

## Version information

**Promotional text (170):**

> See what fills your iPhone, then get space back without losing memories: delete duplicates and junk for free, or shrink videos and Live Photos with Pro.

**Description:**

> Your iPhone is full, and you don't want to delete the memories. SimpleShrink finds what's taking the space and lets you decide what to do with each thing.
>
> FREE
> • See your real free space, and what takes it up: photos, videos, Live Photos, screenshots, bursts and big formats.
> • Find duplicates, blurry and black shots, receipts, documents and old screenshots. You review every one; the best copy of each duplicate stays.
> • Pick what to delete on a review screen. Nothing goes until you confirm.
> • Clean up big files, duplicate copies and old downloads in a folder you pick in Files.
> • Step-by-step guides for space only you can clear: Recently Deleted, WhatsApp, Messages, Safari and unused apps.
> • Measured results: free space is read before and after every cleanup, so you see what really came back.
>
> PRO
> • Shrink 4K videos without deleting them.
> • Trim long recordings to the part you want.
> • Keep Live Photos as stills.
> • Keep the best shot of every burst.
>
> PRIVATE BY DESIGN
> Everything is analysed on your iPhone. SimpleShrink has no account, collects no data and never uploads your photos.
>
> SimpleShrink Pro is available as a weekly or annual auto-renewing subscription, or as a one-time Lifetime purchase. Payment is charged to your Apple ID when you confirm. Subscriptions renew automatically unless cancelled at least 24 hours before the end of the current period, and you can manage or cancel them in Settings → your name → Subscriptions.
>
> Terms of Use: https://<your domain>/terms
> Privacy Policy: https://<your domain>/privacy

**Keywords (97 of 100):**

```
storage,cleaner,space,free up,compress,video,photos,duplicate,cleanup,live photo,burst,files,full
```

The app's name is already indexed, so it isn't repeated here. Apple
rejects brand names in keywords, so there's no "iphone".

**Screenshots:** App Store Connect needs the 6.9" iPhone size, at 1320 × 2868
or 1290 × 2796. CI's screenshots (the **Screenshots** artifact) come from a
6.3" iPhone Pro, so take store screenshots on a 6.9" simulator or device.
They must not show the Test Mode badge if Test Mode is off by then.

## In-app purchases

| Reference name | Product ID | Type | Price | Display name | Description |
|---|---|---|---|---|---|
| Pro Weekly | `com.example.storageapp.pro.weekly` | Auto-renewable, group "Pro", 1 week | $6.99 | Pro Weekly | Shrink videos, trim, Live Photos to stills, burst picks. |
| Pro Annual | `com.example.storageapp.pro.annual` | Auto-renewable, group "Pro", 1 year | $39.99 | Pro Annual | Shrink videos, trim, Live Photos to stills, burst picks. |
| Pro Lifetime | `com.example.storageapp.pro.lifetime` | Non-consumable | $49.99 | Pro Lifetime | Every Pro feature, forever. One payment. |

These match `ios/Products.storekit` and `Plan` in the app. The display names
must stay "Pro Weekly", "Pro Annual" and "Pro Lifetime": the paywall's
disclosure uses those names, and a test checks them against the StoreKit
file.

**Subscription group "Pro":** put **Annual at level 1 and Weekly at level 2**,
as in `Products.storekit`. Each product also needs a **review screenshot** of
the paywall: use `paywall-light.png` from CI's Screenshots artifact.

The first subscription has to be submitted together with an app version.

## App Review notes

Paste this into **App Review Information → Notes**. No sign-in is needed.

> SimpleShrink needs no account.
>
> The app is in Test Mode for this release: it reads and changes only a photo album named exactly "Storage App Test", so it can never touch the rest of a person's library. To review:
>
> 1. In Photos, create an album named Storage App Test and add some photos and videos to it: ideally a duplicate, a Live Photo, a burst and a video longer than a minute.
> 2. Open SimpleShrink, go through onboarding, and allow Full Access to Photos when iOS asks.
> 3. Home shows the album's contents. Pick what to delete opens the review screen; Duplicates and junk is free; Live Photos to stills, Shrink videos and Best shot of each burst are Pro and open the paywall.
>
> Every deletion is reviewed on screen and confirmed by iOS. Photos go to Recently Deleted, and the app then shows how to empty it and measures the space that comes back.
>
> Pro can be bought from the paywall (weekly, annual, or the one-time Lifetime offer shown after closing the paywall), restored from the paywall or Settings → Pro → Restore Purchases, and managed from Settings → Pro → Manage Subscription.
>
> The Files cleanup reads only a folder the reviewer picks in the Files picker.

**Contact information:** your name, phone number and email.
