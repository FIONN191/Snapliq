#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/macos work/region-recording-0.2.2
clang++ -mmacosx-version-min=14.0 -std=c++20 -O2 -I core/include -c core/src/geometry.cpp -o .build/macos/geometry.o
FLAGS=(-swift-version 5 -O -target arm64-apple-macosx14.0 -module-cache-path .build/macos/ModuleCache -import-objc-header core/include/snapliq_core.h)
COMMON=(apps/macos/Support.swift apps/macos/MaterialSurface.swift apps/macos/CaptureBackend.swift apps/macos/RecordingRegion.swift)
LINK=(.build/macos/geometry.o -lc++ -framework AppKit -framework ScreenCaptureKit -framework Carbon -framework ImageIO -framework ServiceManagement)
swiftc "${FLAGS[@]}" "${COMMON[@]}" tests/macos/RecordingRegionTests.swift "${LINK[@]}" -o .build/macos/region_tests
.build/macos/region_tests
if [[ "${1:-}" == "--run-interactive" ]]; then
 swiftc -O tests/macos/RegionFixture.swift -o .build/macos/region_fixture
 swiftc "${FLAGS[@]}" "${COMMON[@]}" apps/macos/Orb.swift apps/macos/RecordingController.swift apps/macos/RecordingEncoder.swift apps/macos/RecordingUI.swift tests/macos/RegionRecordingLiveTests.swift "${LINK[@]}" -framework AVFoundation -framework CoreAudio -o .build/macos/region_recording_tests
 .build/macos/region_recording_tests work/region-recording-0.2.2 .build/macos/region_fixture
 ffmpeg -v error -xerror -i work/region-recording-0.2.2/region.mp4 -fps_mode passthrough -enc_time_base demux -f null -
fi
if [[ "${1:-}" == "--run-interactive" ]]; then
 swiftc "${FLAGS[@]}" "${COMMON[@]}" apps/macos/Orb.swift apps/macos/SmartSelection.swift apps/macos/TextAndSharing.swift apps/macos/Selection.swift tests/macos/RegionSelectionUITests.swift "${LINK[@]}" -framework Vision -o .build/macos/region_selection_ui
 .build/macos/region_selection_ui
fi
