#!/usr/bin/env bash
# Renders index.html into six 1320 x 2868 PNGs (the 6.9" iPhone size App Store
# Connect asks for) in png/. Needs Chrome and an internet connection for the fonts.
# Run from Git Bash:  bash marketing/app-store/render.sh
set -euo pipefail
cd "$(dirname "$0")"
CHROME="${CHROME:-/c/Program Files/Google/Chrome/Application/chrome.exe}"
mkdir -p png
for n in 1 2 3 4 5 6; do
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
    --window-size=1320,2868 --virtual-time-budget=8000 \
    --screenshot="$(cygpath -w "$PWD/png/0$n.png")" \
    "file:///$(cygpath -m "$PWD/index.html")?shot=$n" >/dev/null 2>&1
  echo "png/0$n.png"
done
# A contact sheet of all six, for a quick look.
"$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
  --window-size=1880,700 --virtual-time-budget=8000 \
  --screenshot="$(cygpath -w "$PWD/png/overview.png")" \
  "file:///$(cygpath -m "$PWD/index.html")" >/dev/null 2>&1
echo "png/overview.png"
