#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/macos work/service-tests
COMMON=(apps/macos/Support.swift apps/macos/MaterialSurface.swift apps/macos/CaptureBackend.swift apps/macos/RecordingRegion.swift)
FLAGS=(-swift-version 5 -O -target arm64-apple-macosx14.0 -module-cache-path .build/macos/ModuleCache -import-objc-header core/include/snapliq_core.h)
FRAMEWORKS=(-lc++ -framework AppKit -framework ScreenCaptureKit -framework Carbon -framework ImageIO -framework ServiceManagement)
swiftc "${FLAGS[@]}" "${COMMON[@]}" apps/macos/TextAndSharing.swift apps/macos/RecordingEncoder.swift tests/macos/ServiceTests.swift .build/macos/geometry.o "${FRAMEWORKS[@]}" -framework Vision -framework AVFoundation -o .build/macos/service_tests
.build/macos/service_tests work/service-tests
swiftc "${FLAGS[@]}" "${COMMON[@]}" apps/macos/DesktopBridge.swift tests/macos/BridgeHarness.swift .build/macos/geometry.o "${FRAMEWORKS[@]}" -o .build/macos/bridge_tests
python3 tests/native-bridge.py
node --test tests/chrome-protocol.test.mjs

swiftc "${FLAGS[@]}" "${COMMON[@]}" apps/macos/SmartSelection.swift tests/macos/SmartSelectionTests.swift .build/macos/geometry.o "${FRAMEWORKS[@]}" -o .build/macos/smart_selection_tests
.build/macos/smart_selection_tests
