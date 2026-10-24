# Storage App — iOS

Native iPhone app, built with Swift and SwiftUI for iOS 17 and later.

**Phase 1 runs only in Demo Mode.** Everything works on a generated sample library held in memory. The app does not import PhotoKit, does not request Photos permission, does not read or write device files, and makes no network requests. Deleting and compressing only change the sample data.

## Project layout

```
ios/
├── project.yml                 XcodeGen spec (the .xcodeproj is generated, not committed)
├── StorageCore/                Swift package: all platform-independent logic (Foundation only)
│   ├── Package.swift
│   ├── Sources/StorageCore/
│   │   ├── Models/             MediaItem, MediaCategory/MediaFormat, LibrarySummary, SessionSavings
│   │   ├── Logic/              MediaQuery (filter + sort), MediaSelection, CompressionModel, MediaLibrary
│   │   ├── Formatting/         ByteFormatter, DurationFormatter
│   │   ├── Mocks/              DemoScenario, MockMediaFactory (seeded, deterministic)
│   │   └── Services/           MediaLibraryService protocol, MockMediaLibraryService (actor)
│   └── Tests/StorageCoreTests/ 47 unit tests; run anywhere with `swift test`
├── StorageApp/                 The iOS app target
│   ├── App/                    StorageApp.swift (@main), RootView (tabs, review sheet, alerts)
│   ├── ViewModels/             AppModel: shared @Observable state
│   ├── Views/
│   │   ├── Home/               Dashboard
│   │   ├── Library/            Grid/list browser, cells, detail sheet
│   │   ├── Cleanup/            Review screen and result screen
│   │   ├── Settings/           Demo status, sample libraries, reset, version
│   │   └── Components/         Theme, illustrations, thumbnails, shared views
│   └── Resources/Assets.xcassets   App icon, accent and launch colors, illustrations
├── StorageAppTests/            App-level tests for AppModel (need Xcode)
└── Tools/
    ├── illustrations/generate.py   Generates the hand-inked SVG illustrations
    └── check-no-device-access.sh   Fails if code references Photos, file deletion, or networking
```

## Architecture

Four layers, each depending only on the ones below it:

1. **Models and logic (`StorageCore`).** Plain Swift value types with no UI or Apple-only imports. `LibrarySummary` derives every dashboard number from the items, `MediaQuery` filters and sorts, `CompressionModel` estimates savings and explains unsupported items, and `MediaLibrary` applies simulated delete/compress with an undo stack. Because the package depends only on Foundation, its tests run on Windows, Linux, and macOS.
2. **Service boundary (`MediaLibraryService`).** An async protocol for loading items, deleting, compressing, and undoing. Phase 1 ships one implementation, `MockMediaLibraryService`, an actor wrapping a `MediaLibrary`. Demo-only controls (switching scenario, reset) live in a separate `DemoLibraryControlling` protocol, so a real service never has to fake them.
3. **App state (`AppModel`).** One `@Observable`, `@MainActor` class injected through the SwiftUI environment. It holds the current item snapshot, the selection, filters, sort, tab, and sheet state, and calls the service for every change. After each operation it reloads from the service, so the dashboard, library, and review screens always show the same data.
4. **Views.** SwiftUI views read `AppModel` and call its methods. They contain no business logic.

A Phase 2 `PhotoKitMediaLibraryService` will implement the same protocol (mapping `PHAsset` to `MediaItem`) and be passed to `AppModel` instead of the mock. Views will not need to change.

### Demo data

`MockMediaFactory` builds each scenario from a fixed seed with a SplitMix64 generator, so a scenario is identical on every reset and every run.

| Scenario | Contents |
| --- | --- |
| Typical Library | 2,900 photos, 340 videos, 460 screenshots (~3,700 items) |
| Large Library | 15,600 photos, 1,900 videos, 2,500 screenshots (20,000 items) |
| Empty Library | Nothing, for empty states |

Sizes follow a realistic shape: mostly 2–5 MB HEIC photos with some JPEGs and a few large ProRAW files; videos from a few seconds to 30 minutes at 1080p or 4K (HEVC, H.264, and occasional ProRes); screenshots from 150 KB to 4 MB. Thumbnails are drawn with `Canvas` from each item's seed, so no image files or network requests are involved.

### Simulated compression

`CompressionModel` applies a ratio to each item's original size: for example, Balanced brings videos to 45%, photos to 62%, and screenshots to 35%. ProRAW and ProRes items are reported as unsupported (people keep them for editing), files under 200 KB are "too small", and an item already compressed at the chosen level or stronger is "already compressed". The review screen lists skipped items with the reason instead of pretending they were compressed.

## Building on a Mac

Requirements: macOS with Xcode 15.3 or newer (Xcode 16 recommended) and [Homebrew](https://brew.sh).

```bash
brew install xcodegen
cd ios
xcodegen generate          # creates StorageApp.xcodeproj and StorageApp/Info.plist
open StorageApp.xcodeproj
```

Run `xcodegen generate` again whenever you add, move, or delete files, or edit `project.yml`.

### Run in the iOS Simulator

In Xcode, pick the **StorageApp** scheme and any iPhone simulator, then press **⌘R**. From the command line:

```bash
cd ios
xcodebuild build -project StorageApp.xcodeproj -scheme StorageApp -destination 'platform=iOS Simulator,name=iPhone 16'
```

Use any simulator name that `xcrun simctl list devices available` shows.

### Install on a physical iPhone

1. Connect the iPhone by cable (or pair it over Wi-Fi in Xcode's Devices window) and enable **Developer Mode** on the phone (Settings → Privacy & Security → Developer Mode).
2. In Xcode, select the **StorageApp** target → **Signing & Capabilities**, check **Automatically manage signing**, and choose your Team. A free Apple ID works for personal builds that last 7 days.
3. If Xcode reports the bundle ID is taken, change `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml` (for example to `com.yourname.storageapp`) and regenerate. You can also set `DEVELOPMENT_TEAM` there so regeneration keeps it.
4. Pick your iPhone as the run destination and press **⌘R**. The first time, trust the developer certificate on the phone under Settings → General → VPN & Device Management.

Demo Mode is safe on a personal phone: the app has no Photos permission string, so iOS would refuse any Photos access even if code tried.

## Tests

**Core logic, on any OS** (macOS, Linux, or Windows with the [Swift toolchain](https://www.swift.org/install/)):

```bash
cd ios/StorageCore
swift test
```

Covers byte formatting, storage totals, filters, sorting, selection, compression estimates and plans, simulated delete/compress/undo, deterministic scenario generation, demo reset, and empty-library handling.

**App-level tests, on a Mac** (exercise `AppModel` against the mock service):

```bash
cd ios
xcodebuild test -project StorageApp.xcodeproj -scheme StorageApp -destination 'platform=iOS Simulator,name=iPhone 16'
```

Or press **⌘U** in Xcode.

**Safety check:** `bash ios/Tools/check-no-device-access.sh` fails if any code references PhotoKit, file deletion, video export, or `URLSession`.

### Continuous integration

`.github/workflows/ios.yml` runs on changes under `ios/`. On a macOS runner it runs the safety check and `swift test`, then installs XcodeGen, generates the project, builds the app for the iOS Simulator, and runs the app tests. Nothing is signed, deployed, or published.

### Seeing the app without a Mac

Every CI run uploads two downloadable artifacts (GitHub → Actions → the run → **Artifacts**):

- **Screenshots**: every main screen in light and dark mode, taken in the iOS Simulator. CI opens each screen by launching the app with `-screenshotScreen <name>` (see `App/ScreenshotRoute.swift`).
- **StorageApp-unsigned-ipa**: an unsigned device build for installing with Sideloadly.

#### Installing on an iPhone from Windows with Sideloadly (free)

1. Install Apple's device drivers: the **Apple Devices** app from the Microsoft Store (or iTunes from apple.com).
2. Install [Sideloadly](https://sideloadly.io) for Windows.
3. Download the `StorageApp-unsigned-ipa` artifact from the latest CI run and unzip it to get `StorageApp-unsigned.ipa`.
4. Connect the iPhone by USB, unlock it, and tap **Trust** on the phone.
5. In Sideloadly, drag in the `.ipa`, choose the iPhone, enter an Apple ID (a free one works; a secondary Apple ID is a sensible choice because Sideloadly signs in to Apple with it), and click **Start**.
6. On the iPhone: Settings → Privacy & Security → **Developer Mode** → on (the phone restarts). Then Settings → General → VPN & Device Management → trust your Apple ID.

With a free Apple ID the app stops opening after 7 days; re-run step 5 to refresh it. A free account can have up to 3 sideloaded apps at a time.

### Developing on Windows

Install the Swift toolchain with `winget install Swift.Toolchain` (it also needs Visual Studio Build Tools with the C++ workload and a Windows SDK). Open a new terminal afterwards so `PATH` and `SDKROOT` are set, then run `swift test` in `ios/StorageCore`. SwiftUI and UIKit are not available on Windows, so the app target itself can only be compiled on a Mac or in CI; `swiftc -parse` can still catch syntax errors in app files.

To build the full app and install it on an iPhone from Windows (through WSL2), see [XTOOL_SETUP.md](XTOOL_SETUP.md).

## Changing demo datasets

- **In the app:** Settings → Sample Library. Switching or resetting regenerates the chosen library and discards simulated changes.
- **Default at launch:** change the scenario passed in `AppModel.demo(scenario:)` (`StorageApp/ViewModels/AppModel.swift`).
- **Sizes or counts:** edit `DemoScenario.counts` and the generators in `MockMediaFactory`. Change a scenario's `seed` to get a different but still repeatable library.

## Illustrations

The hand-inked icons are SVGs generated by `Tools/illustrations/generate.py` (Python 3.9+, no dependencies). Each has a light and a dark variant in `Assets.xcassets/Illustrations`. To add one, write a function decorated with `@icon("ill-name")`, run the script, and add a case to `Illustration` in `Views/Components/Illustration.swift`. `--preview` also writes an HTML contact sheet. The app icon (`AppIcon-1024.png`) is the phone illustration on the cream background.

## What's simulated in Phase 1

- The entire media library, its sizes, and its thumbnails.
- Deletion: removes items from the in-memory sample library; undo restores them in place.
- Compression: replaces sizes with model estimates; undo restores originals.
- "Potential space to recover": all screenshots plus estimated Balanced compression of eligible photos and videos.

Nothing persists between launches; each launch starts from the Typical Library.

## Future phases

- PhotoKit service with a clear permission flow, and limited-library support.
- Real deletion through PhotoKit's system confirmation (items go to Recently Deleted).
- Real video compression with AVFoundation, and supported photo re-encoding.
- Duplicate and similar-photo detection.
- iCloud-aware sizing and storage reporting.
- StoreKit 2 purchases, if the app uses them.
- App Store preparation: privacy manifest, screenshots, TestFlight.
