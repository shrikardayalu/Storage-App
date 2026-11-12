#!/usr/bin/env bash
# Builds (and by default installs and launches) the app with xtool from WSL/Linux.
# Copies ios/ into the Linux home folder first, because building on /mnt/c (and
# inside OneDrive) is slow and would sync build output. See ios/XTOOL_SETUP.md.
#
# Usage:  bash ios/Tools/xtool-dev.sh [run|build] [xtool args…]
# Default: run, in release (many times faster than debug for photo scans).
# Override with XTOOL_CONFIGURATION=debug for an unoptimized build.
# Set XTOOL_WORKDIR to change the copy's location (default: ~/storage-app-ios).

set -euo pipefail

# `wsl -- bash ...` from Windows skips the login profile that puts swiftly's Swift on PATH.
if ! command -v swift >/dev/null; then
    . "${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}/env.sh"
fi

# Reach the iPhone through Apple Devices' usbmuxd on Windows (needs WSL mirrored
# networking). usbipd passthrough hangs on install (xtool#19). Set it empty to use local usbmuxd.
export USBMUXD_SOCKET_ADDRESS="${USBMUXD_SOCKET_ADDRESS-127.0.0.1:27015}"
[ -n "$USBMUXD_SOCKET_ADDRESS" ] || unset USBMUXD_SOCKET_ADDRESS

src="$(cd "$(dirname "$0")/.." && pwd)"
dest="${XTOOL_WORKDIR:-$HOME/storage-app-ios}"
cmd="${1:-run}"
if (($# > 0)); then shift; fi
configuration="${XTOOL_CONFIGURATION:-release}"

# Excluded paths aren't deleted in the copy, so .build stays as an incremental cache.
rsync -a --delete \
    --exclude .build --exclude xtool/ --exclude .bsp --exclude ci-artifacts \
    "$src/" "$dest/"

cd "$dest"
exec xtool dev "$cmd" -c "$configuration" "$@"
