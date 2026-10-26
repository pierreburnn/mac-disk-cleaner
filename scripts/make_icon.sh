#!/bin/bash
# Construit Resources/AppIcon.icns à partir de Resources/AppIcon.png (1024x1024)
set -euo pipefail
cd "$(dirname "$0")/.."
SRC="Resources/AppIcon.png"
OUT="${1:-build/AppIcon.icns}"
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET" "$(dirname "$OUT")"
for s in 16 32 128 256 512; do
  sips -z $s $s "$SRC" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  d=$((s*2))
  sips -z $d $d "$SRC" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$OUT"
echo "Icon: $OUT"
