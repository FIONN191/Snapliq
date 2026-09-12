# Approved continuation · 2026-09-06
The user explicitly requested completion of the remaining product after approving the native-host architecture. Continue within that approved design; no second design-approval gate.

1. Preserve the authorized 0.1.0 application; build 0.2.0 candidates separately under outputs/candidate.
2. Local Vision Chinese/English OCR, editable result window; NSSharingService AirDrop with temporary-file lifecycle.
3. Optional window/Accessibility smart selection: snapshot window list before overlay; throttled per-application hit testing with bounded timeout, no OCR or image work on pointer move.
4. ScreenCaptureKit recording with AVAssetWriter, screen/window source, bounded queues, real pause timeline correction, system audio and microphone where supported; independent native control panel; interruption finalization. Region video remains excluded until actual video cropping is implemented.
5. Compile native services; synthetic image/OCR and recording-timeline tests. Then build and exercise capture/recording on the candidate only after its OS permissions are available.
6. Complete Windows native service counterparts and compile where tooling permits. Mark physical Windows checks unavailable without a Windows machine.
7. Only after desktop service implementation, add a constrained Native Messaging adapter and MV3 companion. Bridge request processing must never own desktop lifetime.
8. Preserve exact tested/unverified status, source and binaries. No certificate, release identifier or system privacy database changes without explicit configuration.
