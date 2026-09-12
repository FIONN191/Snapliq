# Snapliq 0.2.2: macOS native region recording
2026-09-13. Continue the user's approved native desktop architecture and remaining-feature request; Chrome store submission remains paused. No release identifiers, signatures or data-directory changes. Keep the verified 0.2.1 app and ZIP intact.

## Decision
Use a display SCContentFilter excluding Snapliq plus SCStreamConfiguration.sourceRect. The installed 15.5 SDK documents sourceRect in display logical points; output width/height are pixels. This crops before encoding and keeps bounded queues. Full-screen recording followed by an export crop adds disk/encoding cost and risks retaining pixels outside the intended region; custom per-frame GPU cropping adds complexity without a demonstrated need. Window recording remains a separate source type.

## User flow
Recording source picker offers “框选录制区域…”. Hide it, reuse the native selection overlay with only Cancel / Use region actions, allow resizing/moving and Enter/Esc. Confirmation returns to the recording picker with a distinct region source, actual encoded pixel dimensions and the existing audio toggles and Save panel. Screenshot mode's “屏幕录制” carries an existing selection into this same region flow. No recording starts before Save confirmation.

## Boundaries
Single-display regions only in this increment. Reject cross-display regions instead of silently choosing a monitor. Convert AppKit global bottom-left coordinates to display-local top-left points. Align inward to whole source pixels and even H.264 dimensions; reject regions smaller than 2×2 encoded pixels. Show actual output size. Revalidate display ID/frame/scale after the Save dialog and before stream start. Stop/finalize using the existing display/sleep/permission lifecycle. Exclude Snapliq by native filter; never capture the UI glass into the export.

## Validation
Pure geometry tests: Retina/1×/fractional DPI, negative monitor coordinates, top/bottom origin, nonfinite/empty/tiny and cross-screen rejection, changed display configuration. Native stream test: generated colored quadrants, asymmetric off-origin region, read actual decoded frame pixels and dimensions, pause/resume/finalization. UI test: Enter chooses region without touching clipboard, Esc releases overlays, source dimensions/cancel/recapture behavior. Build 0.2.2 separately and report module tests separately from final app TCC approval. Windows region recording, cross-screen recording and newer SDK material checks remain out of scope for this increment.

## Sources and design workflow
- Apple: https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/sourcerect
- Installed ScreenCaptureKit SCStream.h sourceRect/destinationRect comments (macOS 15.5 SDK).
- UI UX Pro Max focused search: “keyboard focus modal recording selection” --domain ux; use native named actions, visible focus, edge avoidance, explicit source selection and actual state labels. The existing Snapliq brand/material system remains unchanged.
