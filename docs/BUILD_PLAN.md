# Build Plan: Version 1

A simple, step-by-step plan for building and testing the app. Each step has one goal, what to build, and how to know it works.

## What the app can and can't touch

iOS keeps every app in its own sandbox. This is everything an App Store app is allowed to do that affects storage.

| Area | Can we change it? | Space it can free | Notes |
|---|---|---|---|
| Photos & videos | ✅ Yes, fully | Huge | Delete, compress, trim, Live → still, bursts, duplicates, junk, and big formats like 4K, ProRes, ProRAW, slo-mo |
| Files the user picks (Files app) | ✅ Yes, inside folders the user chooses | Medium–large | Big downloads, zips, PDFs and videos in On My iPhone, Downloads or iCloud Drive. iOS limits us to the picked folder |
| Free space on the phone | 👀 Read only | n/a | Lets us measure, spot "storage is choking", and show a real "you freed X GB" |
| Restart detection | 👀 Read only | n/a | We can tell the phone was restarted, then measure what came back |
| Contacts | ✅ Yes | ~0 | Merging duplicates saves no real space. Skipped for now |
| Recently Deleted | ❌ No | Huge | Only the user can empty it. We guide this, or deleting photos frees nothing for 30 days |
| WhatsApp, Messages, other apps' data | ❌ No | Huge | Locked by iOS. We can open WhatsApp and guide; Messages and Settings are guides only |
| App caches, "System Data", background processes | ❌ No | Huge | Only a restart or iOS clears these. We suggest a restart and measure it |
| Installed apps and their sizes | ❌ No | Large | iOS hides other apps. Guide only ("Offload Unused Apps") |
| The iPhone Storage page in Settings | ❌ Can't open it directly | n/a | We can only open our own Settings page. Everything else is written steps |

**Apple's rule:** never claim to "clean cache", "boost RAM" or "clear system junk". Apple rejects apps that say that. For anything we can't do ourselves, we say "we'll show you how".

**The app works in three layers:**

1. **Do it for you:** photos, videos and picked files.
2. **Spot it and guide you:** restart, Recently Deleted, WhatsApp, Messages, offloading apps.
3. **Measure it:** before/after free space for every action, including the guided ones.

---

## Step 0: Test setup

**Goal:** a safe sandbox so nothing real gets touched.

- [x] **Photos:** a **"Storage App Test"** album on the phone, filled with normal photos, blurry and pocket shots, duplicates, 2 bursts, Live Photos, screenshots, photos of receipts, and long, 4K and short videos.
- [ ] **Files:** make a **"Storage App Test"** folder in Files → On My iPhone before testing Step 8 (see Step 8).
- [ ] **Test Mode:** the app only sees the test album. Built together with Step 2, the first step that reads photos.

**Test:** the app sees nothing outside the test album.

## Step 1: Storage meter

**Goal:** always know how much space the phone has.

- Show used and free space, and save a reading every time the app opens.

**Test:** the numbers roughly match Settings → General → iPhone Storage.

## Step 2: Photo & video scan

**Goal:** see everything and know what takes up space.

- Turn on Test Mode (test album only).
- Total size, biggest first, grouped into photos, videos, Live Photos, screenshots, bursts and big formats.

**Test:** counts and groups match the test album.

## Step 3: Delete safely + empty Recently Deleted guide

**Goal:** deleting actually frees space.

- Select, review, confirm, delete.
- Right after, an animated guide to empty Recently Deleted, then measure the space that came back.

**Test:** only the selected items are deleted, and free space goes up after the guide.

**Built (2026-10-24).** How it stays safe:

- All Photos changes live in one file, `ios/StorageApp/Photos/PhotoLibraryChanges.swift`. `Tools/check-no-device-access.sh` fails CI if change APIs show up anywhere else, or if that file fetches photos library-wide or by ID.
- Right before every change, the app re-reads the album and checks that each approved item is in "Storage App Test" and in no other album. If even one fails, nothing changes. It needs full Photos access (limited access hides albums), and exactly one album with that name.
- iOS shows its own confirmation. Afterwards the app re-reads the album and checks that exactly the approved items left it. The guide shows "48 → 45 items".

**On the phone:** Library → Select → pick a few → Review → Delete. Check that the album lost exactly those, then follow the guide and see "Free space back".

## Step 4: Live Photos → stills

**Goal:** save space without losing photos.

- Keep the date, location, favorite status and album.

**Test:** the photo looks the same and the details are kept.

**Built (2026-10-24).** Each Live Photo is replaced by a new still made from its photo data (the edited version if it has edits, with the EXIF untouched), with the same date, location, favorite, hidden flag and album. The original goes to Recently Deleted in the same change, so declining iOS's prompt leaves no copies. Afterwards the app compares each still with its original and shows a tick per detail. Shots in a burst are left for Step 5, and items that are also in another album are skipped.

**On the phone:** Home → Live Photos → stills. Afterwards, open a converted photo in Photos: no LIVE badge, and the same date, place and heart.

## Step 5: Bursts

**Goal:** keep the best shot and remove the rest.

**Test:** exactly one photo per burst is left, the one the user picked.

**Built (2026-10-29).** Each burst with two or more shots in the test album gets a card with its shots side by side. The camera's pick (or the person's earlier pick in Photos) starts as the keeper, otherwise the middle shot, and tapping another shot picks it instead. A burst can be skipped. Right before the change, the app re-reads the album and rebuilds the plan: one keeper per burst, and the shots to remove must be exactly the other shots the review showed, or nothing changes. Shots to remove go through the same album safety gate as Step 3, so a shot that's also in another album blocks that burst. Afterwards the app re-reads the album and checks that each burst has only its pick left and nothing else changed.

**On the phone:** Home → Best shot of each burst → pick a keeper in each burst → Remove. In Photos, each test burst should show "1 photo" and be the shot you picked. Worth checking: picking a shot that isn't the burst's cover photo. The app's after-check catches it if iOS handles that differently.

## Step 6: Videos (compress + trim)

**Goal:** smaller videos, same memories.

- "Same quality, smaller" and "1080p" options, trim the start and end, and show the size before and after.

**Test:** the video plays, is smaller and keeps its date. Trimming keeps the right part.

**Built (2026-10-30).** Home → Shrink videos lists the test album's videos, biggest first. Each video has a player, a trim bar for the start and end, and the two qualities (both HEVC; 1080p caps the long side at 1920), with an estimated size for each. "Make Smaller Copy" exports to the app's own temporary folder and shows the measured size; nothing in Photos changes until "Replace Video". The copy is refused if it isn't at least 5% smaller. Replacing runs the same album safety gate as Step 3 and refuses if the video was edited since the copy was made. The copy goes into the album with the original's date, location, favorite and hidden flag, and the original goes to Recently Deleted in the same change. Afterwards the app checks the copy's length, size, date, location, favorite and album. Slo-mo, Cinematic and ProRes videos are left alone so they stay editable. Re-encoding and removing files happen only in `StorageApp/Video/VideoExporter.swift`, which `Tools/check-no-device-access.sh` enforces.

**On the phone:** Home → Shrink videos → pick a video → drag the trim handles in a little → 1080p → Make Smaller Copy → Replace Video. In Photos, the video should play, start and end where you trimmed, be smaller (swipe up for the size) and have the same date.

## Step 7: Duplicates + junk

**Goal:** find the stuff people forgot about. Always reviewed, never automatic.

- Duplicates and near-duplicates (best one kept), blurry or black shots, receipts and documents, old screenshots.

**Test:** most planted junk is found, and very few good photos are flagged.

**Built (2026-10-30).** Home → Duplicates and junk measures each photo in the test album on the phone (Vision's feature print and text reading on a 512-pixel copy, plus a brightness and sharpness pass), then lists:

- **Duplicates:** the same photo (any time apart) or near-identical shots taken within an hour, with the same shape. Each copy must be close to every other copy in its group, so a run of similar shots doesn't chain together. The copy with clearly more pixels is kept, then the sharper one, then the bigger file, then the older one. Tapping another copy keeps it instead.
- **Black and pocket shots, blurry shots, receipts, documents:** a photo with lots of text is a document, or a receipt if it also has prices and a word like "total". Screenshots are only ever flagged for being over a month old.

Videos and burst shots are left to Steps 5 and 6. Receipts and documents start unticked. Removing refuses if it would take every copy of a duplicate, or if a kept copy has left the album, then goes through Step 3's delete: the same album safety gate, iOS's confirmation, the after-check and the Recently Deleted guide. All logic and thresholds are in `StorageCore/Logic/JunkFinder.swift` (`JunkRules`), with a planted-album test.

**On the phone:** Home → Duplicates and junk. Check every planted duplicate, blurry, pocket and receipt shot is listed, and count how many good photos are. If too many or too few, the thresholds in `JunkRules` are the starting values to tune.

## Step 8: Files cleanup

**Goal:** clean big files outside of Photos.

- Before starting: make a **"Storage App Test"** folder in Files → On My iPhone with a few big files (videos, zips, PDFs, duplicate copies).
- The user picks a folder, and the app finds large files, duplicate files and old downloads, then reviews and deletes.

**Test:** the app only sees the picked folder, and deleted files are actually gone.

**Built (2026-10-30).** Home → Clean up a folder → Pick a Folder opens iOS's folder picker; iOS lets the app into that folder (and its subfolders) only. The app lists:

- **Duplicate copies:** same size and same SHA-256. The copy whose name doesn't look like a copy ("copy", "(1)", "-1") is kept, then the older one.
- **Large files:** 10 MB or more.
- **Old downloads:** not opened or changed for 6 months.

Hidden files, links and package contents are skipped. Only the extra copies of duplicates start ticked. Deleting is for good (files don't go to Recently Deleted), and the confirmation says so. Right before deleting, the app re-reads the folder and refuses unless every approved file is still there, unchanged (size and date) and strictly inside the picked folder, and every kept copy is too. Afterwards it re-reads the folder, checks exactly those files are gone, and measures free space. Only `StorageApp/Files/PickedFolderFiles.swift` may remove files there, which `Tools/check-no-device-access.sh` enforces.

**On the phone:** make the test folder (a couple of videos, a zip, a PDF, and a PDF duplicated with Files' Duplicate), then Home → Clean up a folder → pick it → delete a duplicate copy and a large file. In Files, those should be gone and nothing else. Note: a copy made with Files' Duplicate shares storage with the original until one is edited, so deleting it may free almost nothing. Copies saved separately (downloaded twice, or AirDropped) free their full size.

## Step 9: Storage health + restart coach

**Goal:** catch the "my phone keeps filling up" problem.

- Warn when free space is very low, or shrinking fast without new photos.
- Suggest a restart with an animated guide (different steps for Face ID and Home-button phones).
- On the next open, detect the restart and show "You got back X GB."

**Test:** the warning shows when space is low, the restart is detected, and the before/after number is right.

**Built (2026-11-05).** Home shows a storage card when free space is under 5 GB (or 5% of a smaller phone, never under 1 GB), or dropped 3 GB or more in 3 days (`StorageCore/Logic/StorageHealth.swift`). "Show Me How" opens the restart guide, with steps for Face ID or Home-button phones (picked from the screen, switchable). "I'm Restarting Now" saves free space as the baseline (`restart-coach.json` in Application Support). On every later reading the app compares the time since the phone started (`CLOCK_MONOTONIC`, which keeps counting while asleep, declared in the privacy manifest as 35F9.1) with the time since the baseline: if the phone started after it, the gain is shown on Home ("You got back X from a restart") and added to Results under Restart. Gains under 20 MB say the restart didn't free much. A baseline nobody restarted after is dropped after 3 days.

**On the phone:** Home needs low space to show the card. Tap Show Me How → I'm Restarting Now, restart, open the app, and check the figure against Settings.

## Screenshot re-save (added 2026-11-05)

**Goal:** the site's "re-save bloated screenshots" promise. iPhone screenshots are PNG; the same image as HEIC at quality 0.9 is usually 60-80% smaller.

**Built.** Home → Re-save screenshots (Pro) lists PNG screenshots in the test album, biggest first, with an estimated saving (35% of the PNG size is assumed for the copy, on the cautious side). Before changing anything the app encodes every copy (`TestAlbumChanges.resaveScreenshots`, ImageIO, same pixels, the PNG's metadata carried over) and keeps only the ones at least 20% smaller. Then one change adds the copies to the album with the original's date, location, favorite and hidden flag and moves the PNGs to Recently Deleted, behind the same album safety gate as Step 3. Afterwards each copy is checked (size, date, favorite, album) and the Recently Deleted guide explains that only the old PNGs are in there.

**On the phone:** take a few screenshots, add them to the test album, re-save them, and check in Photos that each one still opens in Screenshots, looks the same zoomed in, and is smaller (swipe up for the size).

## Step 10: Guides for other apps

**Goal:** help with things the app isn't allowed to touch.

- Animated step-by-step guides:
  - WhatsApp storage (with an "Open WhatsApp" button)
  - Messages large attachments, and "Keep Messages: 1 year"
  - Offload unused apps
  - Safari data
  - Downloaded shows and music
- Each guide ends with a free-space check.

**Test:** the steps match the current iOS and app versions, and the measurement works.

**Built (2026-11-02).** Home → Other apps lists five guides. Each opens full screen: a page on what it frees and why only the person can do it, then one drawn step per screen (ink-in sketches of the screens to look for, built from one phone-and-list drawing in `OtherAppScenes.swift`), then a free-space check.

- **WhatsApp:** Open WhatsApp button (`whatsapp://`; says so if WhatsApp isn't installed) → Settings → Storage and Data → Manage Storage → biggest first → Select, Delete. Last step: Media Auto-Download and Save to Photos so it doesn't fill up again.
- **Messages:** iPhone Storage → Messages → Review Large Attachments → swipe to delete, then Keep Messages → 1 Year (with a red warning that older texts are erased for good, and on other devices with Messages in iCloud), then Messages' own Recently Deleted.
- **Offload unused apps:** iPhone Storage → Enable, the App Store toggle, or Offload App on one app (not Delete App).
- **Safari:** Clear History and Website Data (warns it signs you out), or Advanced → Website Data to keep history.
- **Downloaded shows and music:** iPhone Storage → TV and Music swipe-to-delete, Music's Optimize Storage, and streaming apps' own Downloads pages.

The other guides have an Open Settings button. Apps can only open their own page in Settings, so the button says to tap Back from there. Paths to an app's settings follow the running iOS: Settings → Apps → Safari on iOS 18 and later, Settings → Safari on iOS 17. All the wording is in `StorageApp/Views/Guides/OtherAppGuide.swift`.

The check: opening a guide reads free space. Every return to the app reads it again without moving the person off their step, and a "+X GB" tag shows in the top bar once something came back. The last page reads it a few times and shows the space back. Gains under 20 MB (`FreedLedger.noiseFloor`) count as free space moving on its own, and a guide that freed nothing leaves no result.

**On the phone:** follow each guide for real, and fix any step whose screen or button name doesn't match (WhatsApp's tabs and Messages' Recently Deleted move most between versions). Then delete something big in WhatsApp and check the guide's number roughly matches the size WhatsApp showed.

## Step 11: Results screen

**Goal:** prove the value.

- Total freed, broken down by action (photos, videos, files, guides, restart).

**Test:** the total matches the real change in free space.

**Built (2026-11-02).** Every action reads free space right before it starts and adds an entry to a saved ledger (`StorageCore/Logic/FreedLedger.swift`, saved as `freed-ledger.json` in Application Support). Each later reading is shared out among the actions still being measured, newest first, so two actions measured at the same time never count the same bytes twice. An action with a known size (photos, videos, files) never counts more than that size. A gain stays counted even if free space dips later.

- **Photos** (delete, stills, bursts, duplicates and junk) and **videos** count as Recently Deleted is emptied, for up to 30 days.
- **Files** count right after deleting, for 10 minutes.
- **Guides** count while the guide is open.
- **Restart** is in the breakdown, ready for Step 9 to fill.

Home shows "You've freed X" once anything counted. Home → Results (or that card) shows the total, a bar per action type, every action with its figure, and a "Check it yourself" card: free space before the first action, free space now, the real change, and the counted total, with a tick when they're within 5% (or 20 MB). When they differ, it says whether something else used or freed space in between. "Start Counting Again" clears the totals and changes nothing on the phone. CI also screenshots the WhatsApp guide and the results screen (sample numbers, never saved).

**On the phone:** Results → Start Counting Again. Delete a few photos and empty Recently Deleted, delete a file in the test folder, then do one guide. Without downloading anything in between, the counted total should match "Real change", and each action's figure should be close to what the app said it would free.

## Step 12: Paywall + launch prep

**Goal:** ready for the App Store.

- Turn on the paywall (already built, currently switched off; see `docs/PRICING.md`) and test purchases in sandbox.
- Remove Test Mode from the release build.
- Check that no wording claims to "clean cache" or "boost RAM".
- Build the release through GitHub Actions, then submit to TestFlight.

**Test:** buying, restoring and cancelling work, and the full library works with permission.

## Step 13: Real-phone dry run

**Goal:** trust before launch.

- Scan-only mode on the real library and files: suggestions only, no edits.

**Test:** for every suggestion, "would I actually delete this?" should almost always be yes.

---

## Rules for every step

- Never delete or edit without the user confirming.
- Always keep the date and location.
- Only claim what we actually do. Anything else is a guide.
- Test in the test album first, then dry run on the real library, then edit for real.

## If time is tight

**Must-haves:** Steps 0–7, 11, 12 and 13. Everything the site promises (trim, Live Photos → stills, burst picks) is in there.

**Can move to version 1.1:** Steps 8–10 (Files cleanup, restart coach, other-app guides).
