#!/bin/bash
# Builds Wildmutt.app: the release binary, the bundled Mole engine and the icon, ad-hoc signed.
# Usage: scripts/bundle.sh [output dir]   (default: build/)
set -euo pipefail

cd "$(dirname "$0")/.."
OUT="${1:-build}"
mkdir -p "$OUT"
touch "$OUT/.metadata_never_index"
APP="$OUT/Widmut.app"
VERSION="$(cat VERSION 2>/dev/null || echo 0.1.0)"
MOLE_VERSION="$(cat Vendor/mole/VERSION)"

swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/Wildmutt"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Widmut"
mkdir -p "$APP/Contents/Frameworks"
ditto "$(dirname "$BIN")/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
cp -R Vendor/mole "$APP/Contents/Resources/mole"
cp LICENSE "$APP/Contents/Resources/LICENSE"

# Icon: build the .icns with every size macOS asks for using the original logo
ICONSET="$(mktemp -d)/Widmut.iconset"
mkdir -p "$ICONSET"
ORIG_ICON="docs/icon.png"
cp "$ORIG_ICON" "$ICONSET/icon_512x512.png"
for s in 16 32 128 256; do
    sips -z $s $s "$ORIG_ICON" --out "$ICONSET/icon_${s}x${s}.png" > /dev/null
    sips -z $((s * 2)) $((s * 2)) "$ORIG_ICON" --out "$ICONSET/icon_${s}x${s}@2x.png" > /dev/null
done
sips -z 1024 1024 "$ORIG_ICON" --out "$ICONSET/icon_512x512@2x.png" > /dev/null
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Widmut.icns"
rm -rf "$ICONSET"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Widmut</string>
    <key>CFBundleDisplayName</key><string>Widmut</string>
    <key>CFBundleIdentifier</key><string>io.widmut.mac</string>
    <key>CFBundleExecutable</key><string>Widmut</string>
    <key>CFBundleIconFile</key><string>Widmut</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>MoleVersion</key><string>$MOLE_VERSION</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>GPL-3.0. Widmut Mac Cleaner.</string>
    <key>SUFeedURL</key><string>https://github.com/VedasarathiV/widmut/releases/latest/download/appcast.xml</string>
    <key>SUPublicEDKey</key><string>QaDnpjb2kiIdqemydO9gyCCnyPQdQ2TuRqXxdx4cNjU=</string>
    <key>SUEnableAutomaticChecks</key><true/>
    <key>SUAutomaticallyUpdate</key><true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"
echo "Built $APP ($(du -sh "$APP" | cut -f1))"
