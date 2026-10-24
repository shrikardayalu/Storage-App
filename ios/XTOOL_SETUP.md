# Building on Windows with xtool

[xtool](https://github.com/xtool-org/xtool) builds the app with SwiftPM on Linux, then signs it and installs it on an iPhone without a Mac. On Windows it runs inside WSL2. The Mac/Xcode workflow in [README.md](README.md) is unchanged; xtool uses its own files:

| File | Purpose |
| --- | --- |
| `Package.swift` | SwiftPM manifest for the app target (`StorageApp/`), depending on `StorageCore/` |
| `xtool.yml` | Bundle ID, product name, Info.plist overrides, app icon |
| `xtool-Info.plist` | Info.plist keys copied from `project.yml` (keep the two in sync) |
| `Tools/xtool-dev.sh` | Copies `ios/` into WSL and runs `xtool dev` |

## What's installed on this machine

- WSL2 with **Ubuntu-24.04** (Linux user `shrik`)
- **Swift 6.4.1**, installed with [swiftly](https://www.swift.org/install/linux/) in `~/.local/share/swiftly`
- **xtool** at `/usr/local/bin/xtool`, the AppImage from GitHub Releases
- **usbmuxd** and **libimobiledevice-utils** (`idevice_id`, `ideviceinfo`, `idevicepair`, `idevicesyslog`)
- **usbipd-win** on Windows, for USB passthrough to WSL
- The **Darwin SDK**, built from `Xcode_27.1.xip` (`swift sdk list` shows `darwin`)

xtool, Swift and the device tools live inside WSL, not Windows. In PowerShell, prefix commands with `wsl -d Ubuntu-24.04 --` (for example `wsl -d Ubuntu-24.04 -- xtool auth status`), or open a Linux shell with `wsl -d Ubuntu-24.04` and type them there.

Check everything at once from PowerShell:

```powershell
wsl -d Ubuntu-24.04 -- bash -lc "swift --version; xtool --version; xtool sdk status; xtool auth status; xtool devices"
```

## 1. Open the project in WSL

The repo stays where it is, in OneDrive on Windows; edit Swift files with any Windows editor. WSL sees it at:

```
/mnt/c/Users/shrik/OneDrive/Desktop/Storage App/ios
```

Don't build in that folder directly. Builds on `/mnt/c` are slow, and OneDrive would try to sync the build output. `Tools/xtool-dev.sh` copies `ios/` to `~/storage-app-ios` inside WSL, keeps the build cache there between runs, and builds the copy.

To open a WSL shell, run `wsl -d Ubuntu-24.04` (or pick Ubuntu-24.04 in Windows Terminal). For editor support, open the copy from VS Code's WSL extension (`code ~/storage-app-ios`). xtool writes a `.bsp/` file there for SourceKit-LSP.

## 2. Connect the iPhone

usbipd shares the phone with WSL. The device is already bound (`--force`, so Windows doesn't hold it), so after each reconnect only one step is needed:

1. Connect the iPhone by USB and unlock it.
2. Keep a WSL window open; usbipd needs a running WSL instance.
3. In PowerShell (no admin needed):

   ```powershell
   usbipd list                          # find "Apple iPhone" (VID 05ac); note its BUSID
   usbipd attach --wsl --busid <BUSID>  # e.g. 2-1; it changes with the USB port
   ```

4. Check from WSL:

   ```bash
   idevicepair validate   # "SUCCESS: Validated pairing"
   xtool devices          # "iPhone [usb]: <udid>"
   ```

If the phone shows **Trust This Computer?**, tap Trust and enter the passcode.

While it's force-bound, Windows can't see the phone (no photo import in Explorer or the Photos app). To give it back to Windows, run this in an **admin** PowerShell:

```powershell
usbipd unbind --busid <BUSID>
```

To share it with WSL again afterwards, run `usbipd bind --force --busid <BUSID>` (admin), then unplug and replug the phone.

## 3. Sign in to Apple (once)

Run this yourself in a terminal; it asks for your credentials interactively:

```bash
xtool auth login
```

- Choose **1: Password** for a free Apple ID, or **0: API Key** with a paid developer account (a Team Key with the App Manager role).
- Enter the Apple ID, password and 2FA code only at xtool's prompts. Never put them in files, scripts, or chat.
- `xtool auth status` shows whether you're signed in.

Free Apple ID limits: an app stops launching **7 days** after it's installed (run `xtool dev` again to refresh it), you can have at most 3 sideloaded apps on the device at once, and you can register only a few new bundle IDs per week.

## 4. Build, install and run

From PowerShell:

```powershell
wsl -d Ubuntu-24.04 -- bash "/mnt/c/Users/shrik/OneDrive/Desktop/Storage App/ios/Tools/xtool-dev.sh"
```

Or from a WSL shell:

```bash
bash "/mnt/c/Users/shrik/OneDrive/Desktop/Storage App/ios/Tools/xtool-dev.sh"         # build, install, launch
bash "/mnt/c/Users/shrik/OneDrive/Desktop/Storage App/ios/Tools/xtool-dev.sh" build   # compile only
```

`run` (the default) builds, signs with your Apple ID, installs on the connected iPhone, and launches the app. The built app is at `~/storage-app-ios/xtool/StorageApp.app`.

**First install only, on the iPhone:**

1. Settings → Privacy & Security → **Developer Mode** → on. The phone restarts; confirm when asked. The option appears only after a development app has been installed, so if the first launch fails, enable it and run again.
2. If iOS says the developer isn't trusted: Settings → General → VPN & Device Management → your Apple ID → **Trust**.

## 5. The edit → test loop

1. Edit Swift files in `ios/StorageApp` or `ios/StorageCore` on Windows.
2. Make sure the phone is attached (`xtool devices`).
3. Run `Tools/xtool-dev.sh` again. Incremental builds take a few seconds.

Logic tests run without a phone:

```bash
cd ~/storage-app-ios/StorageCore && swift test
```

For live app logs, run `idevicesyslog -p StorageApp`.

Add new Swift files under `StorageApp/`; SwiftPM picks them up automatically. On a Mac, run `xcodegen generate` as usual. If you add Info.plist keys to `project.yml`, add them to `xtool-Info.plist` too.

## Known differences from the Xcode build

- **No asset catalog.** xtool can't compile `Assets.xcassets` off macOS ([xtool#123](https://github.com/xtool-org/xtool/issues/123)), so `Package.swift` excludes `StorageApp/Resources`. As a result, the hand-inked illustrations (`IllustrationView`) are blank in xtool builds, and the launch screen uses the default background instead of `LaunchBackground`. Colors are unaffected because they're defined in `Theme.swift`. The app icon comes from `AppIcon-1024.png` through `iconPath` in `xtool.yml`. Mac and CI builds include everything.
- The app target's unit tests (`StorageAppTests`) still need Xcode; `StorageCore` tests run anywhere.
- SwiftPM prints `Invalid Exclude ... StorageApp/Info.plist: File not found`. This is expected: that file exists only after `xcodegen generate` on a Mac.

## Troubleshooting

**Connection**

- *`usbipd attach` says "Device busy"*: Windows still holds the phone. Make sure it's bound with `--force` (`usbipd list` shows "Shared (forced)"), then unplug and replug it.
- *"There is no WSL 2 distribution running"*: open a WSL window and keep it open, then attach again.
- *"There is no device with busid"*: the phone is on a different USB port. Check `usbipd list` and use the new bus ID.
- *`xtool devices` hangs or shows nothing*: in WSL, check `systemctl status usbmuxd` (start it with `sudo systemctl restart usbmuxd`), then run `idevice_id -l`. Unlock the phone.
- *`AFCClient.Error.muxError` during install*: this is a known WSL issue. The official workaround relays usbmuxd from the Apple Devices app on Windows instead of using usbipd: see [xtool#19](https://github.com/xtool-org/xtool/issues/19#issuecomment-2898986718).

**Compilation**

- *"Failed to obtain Swift version"*: Swift isn't on PATH. Use a login shell (`bash -l`) or run `. ~/.local/share/swiftly/env.sh`; `Tools/xtool-dev.sh` does this for you.
- *"Swift SDK ... darwin ... is not currently installed"*: run `xtool sdk status`. Reinstall with `xtool sdk install ~/Xcode_27.1.xip`, and after updating xtool, check its release notes for whether the SDK needs reinstalling.
- *Stale or odd build errors*: `rm -rf ~/storage-app-ios/.build ~/storage-app-ios/xtool` and build again.
- *`$'\r': command not found` or `set: pipefail: invalid option`*: a shell script was checked out with Windows line endings. Run it as `tr -d '\r' < script.sh > /tmp/s.sh && bash /tmp/s.sh`, or fix the endings with `git config core.autocrlf input` and a fresh checkout.

**Signing and login**

- *`This action cannot be completed at this time. (-80045 / -80046)`*: Apple rejected the sign-in. These errors have come in waves that affect every xtool user, for example [xtool#329](https://github.com/xtool-org/xtool/issues/329), fixed in 1.22.2, and the open [xtool#378](https://github.com/xtool-org/xtool/issues/378), where -80046 happens after the 2FA code. Don't retry repeatedly, because Apple may stop sending codes. Watch the issue and update xtool when a fix is released (download the new AppImage over `/usr/local/bin/xtool`), then run `xtool auth login` again.
- *Bundle ID unavailable*: `com.example.storageapp` may already be registered to another team. Change `bundleID` in `xtool.yml` to something unique, such as `com.<yourname>.storageapp`.
- *App installs but won't open*: turn on Developer Mode and trust the developer profile (see section 4). With a free Apple ID, also check that the app isn't more than 7 days old.
- *Maximum number of apps reached*: delete another sideloaded app from the phone (free accounts allow 3).
