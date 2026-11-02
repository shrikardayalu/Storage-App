#!/usr/bin/env bash
# Guards what the app may touch on the device. CI runs this on every change.
#
# 1. Changing Photos is allowed in exactly one file, StorageApp/Photos/TestAlbumChanges.swift,
#    which can only reach the "Storage App Test" album (Build Plan steps 3 to 5).
#    That file may not fetch assets library-wide or by ID: everything it changes
#    must come out of the album's own fetch result.
# 2. Re-encoding video is allowed in exactly one file, StorageApp/Video/VideoExporter.swift,
#    which writes and removes only its own copies in the app's temporary folder
#    (Build Plan step 6). Removing files is allowed there and in
#    StorageApp/Files/PickedFolderFiles.swift, which removes only files inside the
#    folder the person picked in Files (Build Plan step 8). Nothing may use the network.
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

exporter='StorageApp/Video/VideoExporter.swift'
folder_files='StorageApp/Files/PickedFolderFiles.swift'
media='AVAssetExportSession|AVAssetWriter|AVAssetReader'
matches=$(grep -rEn "$media" StorageApp StorageCore/Sources | grep -v "^$exporter:" | strip_comments || true)
if [ -n "$matches" ]; then
  echo "$matches"
  echo "error: only $exporter may re-encode media." >&2
  status=1
fi
removal='removeItem\(at|FileManager\.default\.removeItem|trashItem|replaceItem|moveItem'
matches=$(grep -rEn "$removal" StorageApp StorageCore/Sources | grep -v "^$exporter:" | grep -v "^$folder_files:" | strip_comments || true)
if [ -n "$matches" ]; then
  echo "$matches"
  echo "error: only $exporter and $folder_files may remove files." >&2
  status=1
fi
# The folder cleanup removes only files strictly inside the picked folder.
if [ "$(grep -c 'PickedFolder.contains(root: root' "$folder_files" || true)" -lt 2 ]; then
  echo "error: $folder_files must check PickedFolder.contains before removing." >&2
  status=1
fi
# The exporter removes only files directly inside its own folder.
if ! grep -q 'deletingLastPathComponent() == folder.standardizedFileURL' "$exporter"; then
  echo "error: $exporter must only remove files in its own folder." >&2
  status=1
fi

matches=$(grep -rEn 'URLSession' StorageApp StorageCore/Sources | strip_comments || true)
if [ -n "$matches" ]; then
  echo "$matches"
  echo "error: the app must not use the network yet." >&2
  status=1
fi

photos='import Photos|import PhotosUI|PHPhotoLibrary|PHAsset|PHImageManager|PHCachingImageManager|PhotosPicker|PHFetch|PHObject'
matches=$(grep -rEn "$photos" StorageApp StorageCore/Sources | grep -v '^StorageApp/Photos/' | strip_comments || true)
if [ -n "$matches" ]; then
  echo "$matches"
  echo "error: Photos APIs may only be used in StorageApp/Photos/." >&2
  status=1
fi

[ "$status" -eq 0 ] && echo "OK: Photos changes only in $changes_file, scoped to the test album; re-encoding only in $exporter; file removal only there and in $folder_files; no network."
exit "$status"
