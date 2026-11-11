#!/bin/sh
# Renders the Forge app icon (an ember flame on indigo ink) from tools/icon-work/icon-{ios,mac}.svg into the asset catalogs. Needs resvg (brew install resvg).
set -e
root="$(cd "$(dirname "$0")/.." && pwd)"
ios="$root/App/iOS/Assets.xcassets/AppIcon.appiconset"
mac="$root/App/Mac/Assets.xcassets/AppIcon.appiconset"
resvg -w 1024 -h 1024 "$root/tools/icon-work/icon-ios.svg" "$ios/icon-1024.png"
for base in 16 32 128 256 512; do
  for scale in 1 2; do
    resvg -w $((base * scale)) -h $((base * scale)) "$root/tools/icon-work/icon-mac.svg" "$mac/icon-${base}@${scale}x.png"
  done
done
echo "icons written"
