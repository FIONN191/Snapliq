#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/macos outputs
clang++ -mmacosx-version-min=14.0 -std=c++20 -O2 -I core/include -c core/src/geometry.cpp -o .build/macos/geometry.o
clang++ -mmacosx-version-min=14.0 -std=c++20 -O2 -I core/include tests/core_tests.cpp .build/macos/geometry.o -o .build/macos/core_tests
.build/macos/core_tests
VERSION="$(python3 -c 'import json; print(json.load(open("brand/product.json"))["version"])')"
APP="${SNAPLIQ_APP_PATH:-outputs/builds/$VERSION/Snapliq.app}"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
GLASS_FLAGS=()
SDK_MAJOR="$(xcrun --show-sdk-version | cut -d. -f1)"
if (( SDK_MAJOR >= 26 )); then GLASS_FLAGS=(-D SNAPLIQ_GLASS); fi
swiftc -swift-version 5 -O -target arm64-apple-macosx14.0 -module-cache-path .build/macos/ModuleCache \
  -import-objc-header core/include/snapliq_core.h apps/macos/*.swift .build/macos/geometry.o -lc++ \
  -framework AppKit -framework ScreenCaptureKit -framework Carbon -framework ImageIO -framework ServiceManagement -framework Vision -framework AVFoundation -framework CoreMedia -framework CoreAudio \
  "${GLASS_FLAGS[@]}" -o "$APP/Contents/MacOS/Snapliq"
swiftc -swift-version 5 -O -target arm64-apple-macosx14.0 -module-cache-path .build/macos/ModuleCache apps/bridge-macos/main.swift -framework AppKit -o "$APP/Contents/MacOS/SnapliqBridge"
codesign --force --sign "${SNAPLIQ_SIGNING_IDENTITY:--}" --identifier com.snapliq.bridge.development "$APP/Contents/MacOS/SnapliqBridge"
python3 scripts/bundle-metadata.py "$APP"
if [[ -f assets/generated/Snapliq.icns ]]; then cp assets/generated/Snapliq.icns "$APP/Contents/Resources/AppIcon.icns"; fi
codesign --force --sign "${SNAPLIQ_SIGNING_IDENTITY:--}" --identifier com.snapliq.desktop.development "$APP"
codesign --verify --deep --strict "$APP"
echo "Built standalone arm64 development app: $APP"
