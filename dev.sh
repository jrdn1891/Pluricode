#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

DEV_BUNDLE_ID="com.pluricode.app.dev"
SIGN_ID="${PLURICODE_DEV_SIGN_ID:-Apple Development: Gabriel Jourdan (C6AJQN787F)}"
BUILD_DIR="$PWD/build/dev"
APP="$BUILD_DIR/Pluricode.app"

xcodebuild -project Pluricode.xcodeproj -scheme Pluricode -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  CONFIGURATION_BUILD_DIR="$BUILD_DIR" \
  PRODUCT_BUNDLE_IDENTIFIER="$DEV_BUNDLE_ID" \
  build -quiet

/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName 'Pluricode Dev'" "$APP/Contents/Info.plist"
./build-plurisim.sh "$APP"
codesign --force --deep --sign "$SIGN_ID" "$APP"

pkill -f "$APP/Contents/MacOS/Pluricode" || true
open -n "$APP"
