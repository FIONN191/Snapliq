#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${1:-}" != "--run-interactive" || ( "${2:-}" != "smart" && "${2:-}" != "recording" ) ]]; then
  echo 'Usage: zsh scripts/test-native-interactive-macos.sh --run-interactive smart|recording'
  echo 'Opens generated native windows; requires the respective OS permissions.'
  exit 2
fi
mkdir -p .build/macos work
clang++ -mmacosx-version-min=14.0 -std=c++20 -O2 -I core/include -c core/src/geometry.cpp -o .build/macos/geometry.o
FLAGS=(-swift-version 5 -O -target arm64-apple-macosx14.0 -module-cache-path .build/macos/ModuleCache -import-objc-header core/include/snapliq_core.h)
COMMON=(apps/macos/Support.swift apps/macos/MaterialSurface.swift apps/macos/CaptureBackend.swift apps/macos/RecordingRegion.swift)
LINK=(.build/macos/geometry.o -lc++ -framework AppKit -framework ScreenCaptureKit -framework Carbon -framework ImageIO -framework ServiceManagement)
swiftc -O tests/macos/AccessibilityFixture.swift -o .build/macos/accessibility_fixture
if [[ "$2" == "smart" ]]; then
  swiftc "${FLAGS[@]}" "${COMMON[@]}" apps/macos/SmartSelection.swift tests/macos/AccessibilityLiveTests.swift "${LINK[@]}" -o .build/macos/accessibility_live_tests
  .build/macos/accessibility_live_tests work/accessibility-fixture.json .build/macos/accessibility_fixture
else
  swiftc -O tests/macos/AXControl.swift -o .build/macos/ax_control
  swiftc "${FLAGS[@]}" "${COMMON[@]}" apps/macos/Orb.swift apps/macos/RecordingController.swift apps/macos/RecordingEncoder.swift apps/macos/RecordingUI.swift tests/macos/RecordingControlLiveTests.swift "${LINK[@]}" -framework AVFoundation -framework CoreAudio -o .build/macos/recording_control_tests
  python3 scripts/test-recording-controls-macos.py --run-interactive
fi
