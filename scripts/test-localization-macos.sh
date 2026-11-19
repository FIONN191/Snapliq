#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# -gt 1 || ( $# -eq 1 && "$1" != --run-ui ) ]]; then
  echo 'Usage: scripts/test-localization-macos.sh [--run-ui]' >&2
  exit 2
fi
TEST_DIR=.build/localization-tests
APP="$TEST_DIR/LocalizationTests.app"
mkdir -p "$APP/Contents/MacOS" "$TEST_DIR/ModuleCache"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.snapliq.tests.localization</string>
<key>CFBundleExecutable</key><string>LocalizationTests</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
FLAGS=(-swift-version 5 -Onone -target arm64-apple-macosx14.0 -module-cache-path "$TEST_DIR/ModuleCache" -import-objc-header core/include/snapliq_core.h)
SOURCES=(apps/macos/Support.swift apps/macos/MaterialSurface.swift)
LINK=(-framework AppKit -framework ScreenCaptureKit -framework Carbon -framework ServiceManagement)
if [[ "${1:-}" == --run-ui ]]; then
  echo 'UI checks briefly show generated-image selection, OCR and recording-control windows; no desktop capture, microphone, clipboard or global input is used.'
  clang++ -mmacosx-version-min=14.0 -std=c++20 -O2 -I core/include -c core/src/geometry.cpp -o "$TEST_DIR/geometry.o"
  FLAGS+=(-D LOCALIZATION_UI)
  SOURCES+=(apps/macos/CaptureBackend.swift apps/macos/RecordingRegion.swift apps/macos/SmartSelection.swift apps/macos/TextAndSharing.swift apps/macos/Orb.swift apps/macos/Selection.swift apps/macos/Settings.swift apps/macos/RecordingUI.swift apps/macos/RecordingDestination.swift apps/macos/RecordingController.swift apps/macos/RecordingEncoder.swift)
  LINK+=("$TEST_DIR/geometry.o" -lc++ -framework ImageIO -framework Vision -framework AVFoundation -framework CoreMedia -framework CoreAudio)
fi
swiftc "${FLAGS[@]}" "${SOURCES[@]}" tests/macos/LocalizationTests.swift "${LINK[@]}" -o "$APP/Contents/MacOS/LocalizationTests"
"$APP/Contents/MacOS/LocalizationTests" "$@" --diagnostics-dir "$TEST_DIR/diagnostics"
