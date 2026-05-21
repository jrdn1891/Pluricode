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

DMG="build/Pluricode-${VERSION}.dmg"
rm -f "$DMG"
hdiutil create -volname "Pluricode ${VERSION}" -srcfolder build/Pluricode.app \
  -ov -format UDZO "$DMG"

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

gh release create "$TAG" "$DMG" \
  --title "Pluricode ${VERSION}" \
  --notes "$NOTES"
