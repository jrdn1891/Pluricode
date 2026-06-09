#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Working tree dirty — commit or stash first." >&2
  exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Pluricode/Info.plist)
TAG="v${VERSION}"

if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "Tag $TAG already exists — bump CFBundleShortVersionString in Pluricode/Info.plist." >&2
  exit 1
fi

rm -rf build
xcodebuild -project Pluricode.xcodeproj -scheme Pluricode -configuration Release \
  -destination 'generic/platform=macOS' \
  CONFIGURATION_BUILD_DIR="$PWD/build" build -quiet

BUILD_NUMBER=$(git rev-list --count HEAD)
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" build/Pluricode.app/Contents/Info.plist
codesign --force --deep --sign - build/Pluricode.app

DMG="build/Pluricode-${VERSION}.dmg"
rm -f "$DMG"
hdiutil create -volname "Pluricode ${VERSION}" -srcfolder build/Pluricode.app \
  -ov -format UDZO "$DMG"

DMG_LATEST="build/Pluricode.dmg"
cp "$DMG" "$DMG_LATEST"

git tag -a "$TAG" -m "Pluricode ${VERSION}"
git push origin "$TAG"

PREV_TAG=$(git describe --tags --abbrev=0 "${TAG}^" 2>/dev/null || true)
if [[ -n "$PREV_TAG" ]]; then
  CHANGES=$(git log --pretty=format:'- %s' "${PREV_TAG}..${TAG}")
else
  CHANGES=$(git log --pretty=format:'- %s' "$TAG")
fi

NOTES=$(cat <<EOF
## Install

1. Download \`Pluricode-${VERSION}.dmg\`, open it, drag **Pluricode.app** to **/Applications**.
2. First launch: right-click Pluricode.app → **Open** → **Open**. macOS will warn that the developer is unverified; this is expected — Pluricode is not yet signed with an Apple Developer ID.

## Changes

${CHANGES}
EOF
)

gh release create "$TAG" "$DMG" "$DMG_LATEST" \
  --title "Pluricode ${VERSION}" \
  --notes "$NOTES"

SIGN_UPDATE="${SPARKLE_BIN:+$SPARKLE_BIN/}sign_update"
if ! command -v "$SIGN_UPDATE" >/dev/null 2>&1; then
  SIGN_UPDATE=$(find "$HOME/Library/Developer/Xcode/DerivedData" -name sign_update -path '*Sparkle*' 2>/dev/null | head -1)
fi
if [[ -z "$SIGN_UPDATE" || ! -x "$SIGN_UPDATE" ]]; then
  echo "sign_update not found — set SPARKLE_BIN to Sparkle's bin directory (see NIGHTLY.md)." >&2
  exit 1
fi

SIG=$("$SIGN_UPDATE" "$DMG")
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
URL="https://github.com/${REPO}/releases/download/${TAG}/Pluricode-${VERSION}.dmg"
cat > build/stable.item.xml <<EOF
    <item>
      <title>${VERSION}</title>
      <pubDate>$(date -u +"%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>${BUILD_NUMBER}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
      <enclosure url="${URL}" ${SIG} type="application/octet-stream" />
    </item>
EOF
APPCAST_VERSION="${VERSION}" bash scripts/publish_appcast.sh stable build/stable.item.xml
