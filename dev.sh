#!/bin/bash
set -e
cd "$(dirname "$0")"
xcodebuild -project Pluricode.xcodeproj -scheme Pluricode -configuration Debug -destination 'platform=macOS,arch=arm64' CONFIGURATION_BUILD_DIR="$PWD/build" build -quiet
open -n build/Pluricode.app
