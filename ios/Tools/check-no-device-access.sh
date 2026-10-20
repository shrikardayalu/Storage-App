#!/usr/bin/env bash
# Fails if Phase 1 code references real photo-library or file-deletion APIs.
# Demo Mode must never touch personal media; CI runs this on every change.
# Usage: bash ios/Tools/check-no-device-access.sh
set -euo pipefail

cd "$(dirname "$0")/.."

pattern='import Photos|import PhotosUI|PHPhotoLibrary|PHAsset|PhotosPicker|NSPhotoLibrary|removeItem\(at|FileManager\.default\.removeItem|AVAssetExportSession|URLSession'

# Comment lines (// or #) are allowed to mention these APIs.
matches=$(grep -rEn "$pattern" StorageApp StorageCore/Sources project.yml | grep -vE '^[^:]+:[0-9]+:[[:space:]]*(//|#)' || true)
if [ -n "$matches" ]; then
  echo "$matches"
  echo "error: Phase 1 must not access Photos, delete files, compress real media, or use the network." >&2
  exit 1
fi
echo "OK: no device-media or network APIs referenced."
