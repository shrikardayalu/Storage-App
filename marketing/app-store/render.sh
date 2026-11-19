#!/usr/bin/env bash
# Renders index.html into six PNGs in png/, drawn at 1320 x 2868 and then scaled
# to 1206 x 2622 (the 6.1"/6.3" iPhone size App Store Connect asks for).
# Needs Chrome, Python with Pillow, and an internet connection for the fonts.
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
  python -c "from PIL import Image; p='png/0$n.png'; Image.open(p).convert('RGB').resize((1206,2622), Image.LANCZOS).save(p, optimize=True)"
  echo "png/0$n.png"
done
# A contact sheet of all six, for a quick look.
"$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
  --window-size=1880,700 --virtual-time-budget=8000 \
  --screenshot="$(cygpath -w "$PWD/png/overview.png")" \
  "file:///$(cygpath -m "$PWD/index.html")" >/dev/null 2>&1
echo "png/overview.png"
