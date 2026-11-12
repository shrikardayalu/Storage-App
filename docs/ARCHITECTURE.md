# Architecture

This repository holds several **independent** pieces of one product. They share a Git history but no code, dependencies, or build tooling. There is no monorepo tool or npm workspace; each folder is set up on its own.

```
SimpleShrink/
├── web/          Next.js marketing site (deployed to Vercel)
├── ios/          Native SwiftUI app (built in Xcode on macOS, shipped via App Store Connect)
├── automation/   Planned SEO and content loop (documented, not implemented)
└── docs/         Project documentation
```

## web/

- Next.js (App Router) with React, TypeScript, Tailwind CSS v4, and ESLint, using `src/` and the `@/*` import alias.
- Static, prerendered pages: home, `/guides` hub, one page per guide, about, privacy. No database or accounts. The only server code is the waitlist server action, which forwards signups to `WAITLIST_WEBHOOK_URL`.
- Guides are Markdown files in `web/content/guides/`, loaded and validated at build time by `src/lib/guides.ts` (format: `web/content/README.md`). Broken internal links fail the build.
- SEO/AEO surface: per-page canonicals and Open Graph images, JSON-LD (`src/lib/schema.ts`), `sitemap.xml`, `robots.txt`, `/guides/feed.xml`, and `/llms.txt`.
- Design language matches the app (`Theme.swift`): paper, ink, and mint, with the app's hand-inked illustrations copied into `public/illustrations/`.
- Configuration comes from environment variables. Only `NEXT_PUBLIC_*` values reach the browser, and they are inlined at build time, so they must never hold secrets.
- Deployment: Vercel imports this repository with **Root Directory = `web`**.

## ios/

- Swift and SwiftUI, iOS 17+. The Xcode project is generated from `ios/project.yml` with XcodeGen and is not committed.
- `ios/StorageCore` is a Foundation-only Swift package with the models, scan grouping, storage history, compression estimates, and the `DeviceStorageService` and `PhotoScanService` protocols (with mocks). Its tests run on any OS.
- The app target (`ios/StorageApp`) holds one `@Observable` `AppModel` and the SwiftUI views. It reads real free space and scans the photo library (the whole library with full access, or only the picked photos with limited access). All Photos code lives in `StorageApp/Photos/`. The only changes (delete, Live Photo → still, keep the best shot of a burst, swap a video for a smaller copy) are in `PhotoLibraryChanges.swift`, behind StorageCore's `PhotoChangeService`, and change only items the person approved on a review screen: each is looked up by its ID and re-checked right before the change. Copies that replace an original keep its date, location, favorite and albums. Photo measurements for the junk finder are saved by StorageCore's `PhotoSignalsStore`, so a big library is measured once. Smaller video copies are made by `StorageApp/Video/VideoExporter.swift`, the only code that re-encodes media, and it removes files only in its own temporary folder. The duplicates and junk finder (`JunkFinder` in StorageCore) works from measurements that `StorageApp/Photos/PhotoAnalyzer.swift` takes on the phone with Vision; removals go through the same approved-items delete. Files cleanup reads and deletes only inside the one folder the person picks in Files, in `StorageApp/Files/PickedFolderFiles.swift`, behind StorageCore's `FolderFilesService`. `Tools/check-no-device-access.sh` enforces all of this.
- Guides for other apps (`StorageApp/Views/Guides/`) change nothing; they only open WhatsApp or the app's own Settings page. Every action, guides included, is measured against free space by StorageCore's `FreedLedger`, which the results screen (`StorageApp/Views/Results/`) adds up.
- Later steps add AVFoundation video compression and StoreKit 2, behind protocols in the same way.
- CI: `.github/workflows/ios.yml` runs the core tests and builds/tests the app on a macOS runner.

## automation/

- Planned tooling that produces content (Markdown in `web/content/guides/`) and SEO reports. It is meant to write files for the site, not run inside it. See `automation/README.md` for the loop.

## How they relate

The website markets the app and will eventually link to its App Store listing (`NEXT_PUBLIC_APP_STORE_URL`). The app does not depend on the website. Automation only feeds content into the website. Each piece can be developed, tested, and deployed without the others.
