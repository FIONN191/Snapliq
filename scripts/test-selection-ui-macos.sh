#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${1:-}" != "--run-interactive" ]]; then
  echo "This test opens a generated full-screen selection and temporarily uses the clipboard."
  echo "Run explicitly: zsh scripts/test-selection-ui-macos.sh --run-interactive"
  exit 2
fi
# Run scripts/test-macos.sh first to compile the shared geometry object.
swiftc -swift-version 5 -O -target arm64-apple-macosx14.0 -module-cache-path .build/macos/ModuleCache \
 -import-objc-header core/include/snapliq_core.h apps/macos/Support.swift apps/macos/MaterialSurface.swift \
 apps/macos/CaptureBackend.swift apps/macos/RecordingRegion.swift apps/macos/SmartSelection.swift apps/macos/TextAndSharing.swift \
 apps/macos/Orb.swift apps/macos/Selection.swift tests/macos/SelectionUITests.swift .build/macos/geometry.o \
 -lc++ -framework AppKit -framework ScreenCaptureKit -framework Carbon -framework ImageIO \
 -framework ServiceManagement -framework Vision -o .build/macos/selection_ui
.build/macos/selection_ui
