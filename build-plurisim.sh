#!/bin/bash
# Compiles the plurisim live-stream helper and installs it into an app bundle's Contents/Helpers.
# The helper dlopens Apple's CoreSimulator at runtime, so it links only system frameworks here and
# needs nothing beyond Xcode's command-line tools to build.
set -euo pipefail
cd "$(dirname "$0")"

APP="${1:?usage: build-plurisim.sh <App.app>}"
HELPERS="$APP/Contents/Helpers"
mkdir -p "$HELPERS"

clang -fobjc-arc -O2 \
  -framework Foundation -framework CoreImage -framework IOSurface -framework ImageIO -framework CoreGraphics \
  -o "$HELPERS/plurisim" Plurisim/plurisim.m

echo "build-plurisim: installed $HELPERS/plurisim"
