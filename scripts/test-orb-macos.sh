#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/orb-tests
clang++ -mmacosx-version-min=14.0 -std=c++20 -O2 -I core/include -c core/src/geometry.cpp -o .build/orb-tests/geometry.o
FLAGS=(-swift-version 5 -Onone -target arm64-apple-macosx14.0 -module-cache-path .build/orb-tests/ModuleCache -import-objc-header core/include/snapliq_core.h)
COMMON=(apps/macos/Support.swift apps/macos/MaterialSurface.swift apps/macos/Orb.swift)
LINK=(.build/orb-tests/geometry.o -lc++ -framework AppKit -framework ScreenCaptureKit -framework Carbon -framework ServiceManagement)
swiftc "${FLAGS[@]}" "${COMMON[@]}" tests/macos/OrbPreferencesTests.swift "${LINK[@]}" -o .build/orb-tests/orb_preferences_tests
.build/orb-tests/orb_preferences_tests
