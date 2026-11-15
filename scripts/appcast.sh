#!/bin/bash
# Writes build/appcast.xml for the release in build/Widmut.zip, signed with the Sparkle key in
# the login Keychain (made once with generate_keys). Upload it with the release: every installed
# Widmut reads releases/latest/download/appcast.xml and updates itself from it.
# Usage: scripts/appcast.sh [build dir]   (default: build/, after bundle.sh and the ditto zip)
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="$(cat VERSION)"
OUT="${1:-build}"
ZIP="$OUT/Widmut.zip"
SIGN="$(find .build/artifacts -path '*Sparkle/bin/sign_update' | head -1)"
SIGNATURE="$("$SIGN" "$ZIP")"   # sparkle:edSignature="…" length="…"

cat > "$OUT/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Widmut</title>
    <item>
      <title>Widmut $VERSION</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$VERSION</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
      <link>https://github.com/VedasarathiV/widmut/releases/tag/v$VERSION</link>
      <enclosure url="https://github.com/VedasarathiV/widmut/releases/download/v$VERSION/Widmut.zip"
                 type="application/octet-stream" $SIGNATURE />
    </item>
  </channel>
</rss>
XML
echo "Wrote $OUT/appcast.xml for $VERSION"
