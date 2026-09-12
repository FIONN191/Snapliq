#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/macos
clang++ -mmacosx-version-min=14.0 -std=c++20 -O2 -I core/include -c core/src/geometry.cpp -o .build/macos/geometry.o
clang++ -mmacosx-version-min=14.0 -std=c++20 -O2 -I core/include tests/core_tests.cpp .build/macos/geometry.o -o .build/macos/core_tests
.build/macos/core_tests
swiftc -swift-version 5 -O -module-cache-path .build/macos/ModuleCache \
 -import-objc-header core/include/snapliq_core.h apps/macos/Support.swift apps/macos/MaterialSurface.swift apps/macos/CaptureBackend.swift apps/macos/RecordingRegion.swift \
 tests/macos/ImagePipelineTests.swift .build/macos/geometry.o -lc++ \
 -framework AppKit -framework ScreenCaptureKit -framework Carbon -framework ImageIO -framework ServiceManagement \
 -o .build/macos/image_tests
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp/}snapliq-tests.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
.build/macos/image_tests "$TEST_DIR"
