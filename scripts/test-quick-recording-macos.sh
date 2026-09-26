#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/quick-recording
clang++ -mmacosx-version-min=14.0 -std=c++20 -O2 -I core/include -c core/src/geometry.cpp -o .build/quick-recording/geometry.o
FLAGS=(-swift-version 5 -O -target arm64-apple-macosx14.0 -module-cache-path .build/quick-recording/ModuleCache -import-objc-header core/include/snapliq_core.h)
COMMON=(apps/macos/Support.swift apps/macos/MaterialSurface.swift apps/macos/CaptureBackend.swift apps/macos/RecordingDestination.swift)
LINK=(.build/quick-recording/geometry.o -lc++ -framework AppKit -framework ScreenCaptureKit -framework Carbon -framework ImageIO -framework ServiceManagement)
swiftc "${FLAGS[@]}" "${COMMON[@]}" tests/macos/QuickRecordingTests.swift "${LINK[@]}" -o .build/quick-recording/quick_recording_tests
.build/quick-recording/quick_recording_tests
