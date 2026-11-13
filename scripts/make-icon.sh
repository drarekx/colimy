#!/bin/zsh
# Regenerates Resources/AppIcon.icns, brand/icon-1024.png and the menu bar template image
# (Resources/MenuBarIcon.png + @2x) from brand/icon.svg and brand/menubar.svg.
set -euo pipefail
cd "$(dirname "$0")/.."
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
swiftc -O scripts/tools/render-svg.swift -o "$TMP/render" 2>/dev/null
SET="$TMP/AppIcon.iconset"
mkdir -p "$SET" Resources
for spec in 16:icon_16x16 32:icon_16x16@2x 32:icon_32x32 64:icon_32x32@2x 128:icon_128x128 256:icon_128x128@2x \
            256:icon_256x256 512:icon_256x256@2x 512:icon_512x512 1024:icon_512x512@2x; do
  "$TMP/render" brand/icon.svg "${spec%%:*}" "$SET/${spec#*:}.png"
done
iconutil -c icns "$SET" -o Resources/AppIcon.icns
cp "$SET/icon_512x512@2x.png" brand/icon-1024.png
"$TMP/render" brand/menubar.svg 18 Resources/MenuBarIcon.png
"$TMP/render" brand/menubar.svg 36 Resources/MenuBarIcon@2x.png
echo "Wrote Resources/AppIcon.icns, Resources/MenuBarIcon*.png and brand/icon-1024.png"
