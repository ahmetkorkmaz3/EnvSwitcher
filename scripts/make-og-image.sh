#!/bin/sh
# Render scripts/og-image.html to site/og-image.png (1200x630) with headless Chrome.
set -eu

cd "$(dirname "$0")/.."
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"

"$CHROME" --headless=new --disable-gpu --hide-scrollbars \
  --force-device-scale-factor=1 --window-size=1200,630 \
  --screenshot="$PWD/site/og-image.png" \
  "file://$PWD/scripts/og-image.html" 2>/dev/null

echo "site/og-image.png"
