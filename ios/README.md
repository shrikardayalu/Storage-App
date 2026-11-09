# SimpleShrink — iOS

Native iPhone app, built with Swift and SwiftUI for iOS 17 and later.

**The app runs in Test Mode and only reads.** It measures the phone's real free space (Build Plan step 1) and scans one Photos album, **"Storage App Test"** (step 2). It never deletes, edits, or adds photos, and makes no network requests. With "selected photos" access, iOS hides albums, so the scan reads exactly the photos the person picked.

## Project layout

```
ios/
├── project.yml                 XcodeGen spec (the .xcodeproj is generated, not committed)
├── StorageCore/                Swift package: all platform-independent logic (Foundation only)
│   ├── Package.swift
│   ├── Sources/StorageCore/
│   │   ├── Models/             MediaItem, MediaCategory/MediaFormat, StorageSnapshot, CategoryTotal
│   │   ├── Logic/              LibraryScan (groups), StorageHistory, MediaQuery, MediaSelection, CompressionModel
│   │   ├── Formatting/         ByteFormatter, DurationFormatter
│   │   └── Services/           DeviceStorageService and PhotoScanService protocols, with mocks
│   └── Tests/StorageCoreTests/ Unit tests; run anywhere with `swift test`
├── StorageApp/                 The iOS app target
│   ├── App/                    StorageApp.swift (@main), RootView (tabs, alerts)
│   ├── ViewModels/             AppModel: shared @Observable state
│   ├── Services/               VolumeStorageService (free space), StorageHistoryStore (JSON)
│   ├── Photos/                 The only Photos code: read-only album scan, thumbnails, picker
│   ├── Views/
│   │   ├── Home/               iPhone storage, test album summary, groups
│   │   ├── Library/            Scan results, biggest first, filtered by group
│   │   ├── Settings/           Test Mode, Photos access, debug readings, version
│   │   └── Components/         Theme, illustrations, shared views
│   └── Resources/Assets.xcassets   App icon, accent and launch colors, illustrations
├── StorageAppTests/            App-level tests for AppModel (need Xcode)
└── Tools/
    ├── illustrations/generate.py   Generates the hand-inked SVG illustrations
    └── check-no-device-access.sh   Fails on any change/delete/network API, or Photos outside StorageApp/Photos
```

## Architecture

Four layers, each depending only on the ones below it:

1. **Models and logic (`StorageCore`).** Plain Swift value types with no UI or Apple-only imports. `LibraryScan` groups scanned items and sorts them biggest first, `StorageHistory` keeps up to 500 free-space readings (at most one a minute), `MediaQuery` filters and sorts, and `CompressionModel` estimates savings for the later compression step. Because the package depends only on Foundation, its tests run on Windows, Linux, and macOS.
2. **Service boundary.** `DeviceStorageService` reads free space; `PhotoScanService` reads one album. The real implementations live in the app target (`VolumeStorageService`, `PhotoKitScanService`); StorageCore ships mocks for tests and previews.
3. **App state (`AppModel`).** One `@Observable`, `@MainActor` class injected through the SwiftUI environment. It holds the latest storage reading and history, the latest scan, Photos access, and navigation.
4. **Views.** SwiftUI views read `AppModel` and call its methods. They contain no business logic.

### Storage readings

A reading is taken on launch and whenever the app returns to the foreground, from the home volume's `volumeAvailableCapacity` (shown as free), `volumeAvailableCapacityForImportantUsage` (stored only, for the later storage-health step), and `volumeTotalCapacity`. Capacity is shown as the advertised size (for example 128 GB), as Settings does. Readings are saved as JSON in Application Support. Debug builds list the last 20 in Settings.

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

Test Mode is safe on a personal phone: the app only reads, and with full access it reads only the "Storage App Test" album.

## Tests

**Core logic, on any OS** (macOS, Linux, or Windows with the [Swift toolchain](https://www.swift.org/install/)):

```bash
cd ios/StorageCore
swift test
```

Covers byte formatting, storage readings and history, scan grouping, filters, sorting, selection, and compression estimates.

**App-level tests, on a Mac** (exercise `AppModel` against the mock services):

```bash
cd ios
xcodebuild test -project StorageApp.xcodeproj -scheme StorageApp -destination 'platform=iOS Simulator,name=iPhone 16'
```

Or press **⌘U** in Xcode.

**Safety check:** `bash ios/Tools/check-no-device-access.sh` fails if any code changes photos, deletes files, exports video, or uses `URLSession`, or if Photos APIs appear outside `StorageApp/Photos/`.

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

## Illustrations

The hand-inked icons are SVGs generated by `Tools/illustrations/generate.py` (Python 3.9+, no dependencies). Each has a light and a dark variant in `Assets.xcassets/Illustrations`. To add one, write a function decorated with `@icon("ill-name")`, run the script, and add a case to `Illustration` in `Views/Components/Illustration.swift`. `--preview` also writes an HTML contact sheet. The app icon (`AppIcon-1024.png`) is the phone illustration on the cream background.

## Next steps

See `docs/BUILD_PLAN.md`. In short:

- Real deletion through PhotoKit's system confirmation (items go to Recently Deleted).
- Real video compression with AVFoundation, and supported photo re-encoding.
- Duplicate and similar-photo detection.
- iCloud-aware sizing and storage reporting.
- StoreKit 2 purchases, if the app uses them.
- App Store preparation: privacy manifest, screenshots, TestFlight.
