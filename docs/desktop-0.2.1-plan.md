# Snapliq 0.2.1 desktop continuation
The user explicitly chose desktop development and paused Chrome Web Store submission on 2026-09-08. No store upload or review submission is part of this increment.

Within the previously approved native architecture:
1. Keep the most recent pointer hit while a single AX query is in flight; scope cached boundaries by window and process; cancel late results and deduplicate candidates. Test with deterministic delayed resolvers and a real native button behind our own overlay.
2. Fit screenshot actions to their intrinsic widths plus 16 pt horizontal insets; preserve screen-edge avoidance and keyboard capture actions. Verify actual control bounds and editable OCR/image copying.
3. Give the recording control panel a stable accessible title, identifiers and pause/resume/save semantics; support an explicitly focused keyboard loop while avoiding focus theft during recording. Exercise external AX actions against a real generated-window recording.
4. Build 0.2.1 into a versioned directory. Keep the running, authorized 0.2.0 candidate intact. Do not alter bundle identity, Chrome identity or data location.
5. Report module tests separately from final app TCC validation. New ad-hoc code has a different requirement and may need user action in macOS privacy settings.

Deferred: physical Windows hardware, multiple monitors, macOS 26/27 SDK/runtime, cross-device AirDrop, full microphone/device/sleep/revocation matrix, region recording and browser DOM enhancement.
