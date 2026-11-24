#!/bin/zsh
# Regenerates Resources/AppIcon.icns from Resources/Brand/app-icon.svg. Needs rsvg-convert
# (brew install librsvg).
set -euo pipefail
cd "$(dirname "$0")/.."

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
SET="$WORK/AppIcon.iconset"
mkdir -p "$SET"
for size in 16 32 128 256 512; do
  rsvg-convert -w $size -h $size Resources/Brand/app-icon.svg -o "$SET/icon_${size}x${size}.png"
  rsvg-convert -w $((size * 2)) -h $((size * 2)) Resources/Brand/app-icon.svg -o "$SET/icon_${size}x${size}@2x.png"
done
iconutil -c icns -o Resources/AppIcon.icns "$SET"
echo "Wrote Resources/AppIcon.icns"
