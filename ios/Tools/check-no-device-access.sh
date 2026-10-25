#!/usr/bin/env bash
# Guards what the app may touch on the device. CI runs this on every change.
#
# 1. Changing Photos is allowed in exactly one file, StorageApp/Photos/TestAlbumChanges.swift,
#    which can only reach the "Storage App Test" album (Build Plan steps 3 and 4).
#    That file may not fetch assets library-wide or by ID: everything it changes
#    must come out of the album's own fetch result.
# 2. Nothing may delete files, compress real media, or use the network.
# 3. Reading Photos is allowed only in StorageApp/Photos/. Everywhere else,
#    Photos APIs are off limits.
#
# Usage: bash ios/Tools/check-no-device-access.sh
set -euo pipefail

cd "$(dirname "$0")/.."

# Comment lines (// or #) are allowed to mention these APIs.
strip_comments() { grep -vE '^[^:]+:[0-9]+:[[:space:]]*(//|#|///)' || true; }

changes_file='StorageApp/Photos/TestAlbumChanges.swift'
status=0

photo_changes='performChanges|PHAssetChangeRequest|PHAssetCreationRequest|PHAssetCollectionChangeRequest|deleteAssets|PHContentEditingOutput'
matches=$(grep -rEn "$photo_changes" StorageApp StorageCore/Sources | grep -v "^$changes_file:" | strip_comments || true)
if [ -n "$matches" ]; then
  echo "$matches"
  echo "error: only $changes_file may change Photos." >&2
  status=1
fi

# The change file reaches assets only through the test album.
wide_fetches='fetchAssets\(with|fetchAssets\(withLocalIdentifiers|fetchAssets\(withBurstIdentifier|fetchKeyAssets|fetchAssetCollections\(withLocalIdentifiers|subtype: \.any'
matches=$(grep -En "$wide_fetches" "$changes_file" | sed "s|^|$changes_file:|" | strip_comments || true)
if [ -n "$matches" ]; then
  echo "$matches"
  echo "error: $changes_file may only fetch assets from the test album." >&2
  status=1
fi
if ! grep -q 'TestMode.albumName' "$changes_file"; then
  echo "error: $changes_file must look up the album by TestMode.albumName." >&2
  status=1
fi

other='removeItem\(at|FileManager\.default\.removeItem|AVAssetExportSession|URLSession'
matches=$(grep -rEn "$other" StorageApp StorageCore/Sources | strip_comments || true)
if [ -n "$matches" ]; then
  echo "$matches"
  echo "error: the app must not delete files, compress real media, or use the network yet." >&2
  status=1
fi

photos='import Photos|import PhotosUI|PHPhotoLibrary|PHAsset|PHImageManager|PHCachingImageManager|PhotosPicker|PHFetch|PHObject'
matches=$(grep -rEn "$photos" StorageApp StorageCore/Sources | grep -v '^StorageApp/Photos/' | strip_comments || true)
if [ -n "$matches" ]; then
  echo "$matches"
  echo "error: Photos APIs may only be used in StorageApp/Photos/." >&2
  status=1
fi

[ "$status" -eq 0 ] && echo "OK: Photos changes only in $changes_file, scoped to the test album; nothing deletes files or uses the network."
exit "$status"
