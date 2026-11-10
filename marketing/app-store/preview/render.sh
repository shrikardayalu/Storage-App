#!/usr/bin/env bash
# Renders index.html into the App Store preview video: 886 x 1920, 30 fps, H.264
# High at about 10 Mbps, with a silent stereo AAC track (App Store Connect can
# reject a preview that has no audio track). Also saves the frame at 3.4 s as
# poster.png, a good one to pick as the poster frame.
#
# Needs Chrome, Node 22+, an internet connection for the fonts, and ffmpeg
# (on PATH, or inside WSL). Run from Git Bash:
#   bash marketing/app-store/preview/render.sh
set -euo pipefail
cd "$(dirname "$0")"
FRAMES="$(cygpath -m "$(mktemp -d)")"
node render.mjs "$FRAMES" 30

ENCODE=(-y -loglevel error -framerate 30 -i f_%04d.png
  -f lavfi -i anullsrc=r=48000:cl=stereo
  -vf "scale=886:1920:flags=lanczos,format=yuv420p"
  -c:v libx264 -profile:v high -level 4.0 -preset slow -b:v 10M -maxrate 12M -bufsize 20M
  -r 30 -c:a aac -b:a 256k -ar 48000 -shortest -movflags +faststart preview.mp4)
POSTER=(-y -loglevel error -i f_0102.png -vf "scale=886:1920:flags=lanczos" poster.png)

if command -v ffmpeg >/dev/null; then
  (cd "$FRAMES" && ffmpeg "${ENCODE[@]}" && ffmpeg "${POSTER[@]}")
else
  export MSYS_NO_PATHCONV=1
  WF="$(wsl wslpath -a "$FRAMES" | tr -d '\r')"
  wsl --cd "$WF" ffmpeg "${ENCODE[@]}"
  wsl --cd "$WF" ffmpeg "${POSTER[@]}"
fi
cp "$FRAMES/preview.mp4" simpleshrink-preview.mp4
cp "$FRAMES/poster.png" poster.png
echo "simpleshrink-preview.mp4, poster.png (frames left in $FRAMES)"
