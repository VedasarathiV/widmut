#!/bin/bash
# Packs a built Widmut.app into a drag-to-Applications disk image.
# Usage: scripts/dmg.sh [build dir]   (default: build/, expects build/Widmut.app from bundle.sh)
set -euo pipefail

cd "$(dirname "$0")/.."
OUT="${1:-build}"
APP="$OUT/Widmut.app"
DMG="$OUT/Widmut.dmg"
[[ -d "$APP" ]] || { echo "No $APP; run scripts/bundle.sh first" >&2; exit 1; }

STAGE="$(mktemp -d)/Widmut"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Widmut.app"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
# ULFO (LZFSE) is the smallest format every supported macOS opens.
hdiutil create -volname "Widmut" -srcfolder "$STAGE" -fs HFS+ -format ULFO -ov "$DMG" > /dev/null
codesign --force --sign - "$DMG"
rm -rf "$(dirname "$STAGE")"
echo "Built $DMG ($(du -h "$DMG" | cut -f1))"
