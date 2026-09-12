# Desktop platform contract, v0.1
The desktop host owns process lifetime; the window lifetime is a child of it. Only an explicit Quit unregisters the global shortcut and terminates the process. A settings window close must never stop capture or future recording services.

## Capture lifecycle
Idle → permission check → hide owned surfaces → request fresh native capture → validate display topology → frozen source ready → interactive selection → encode / clipboard or save → Idle.
Error / cancel paths release session windows and restore the orb. The raw frozen source is immutable; overlay drawing never changes export buffers. No OCR, network, animations or passive capture are permitted on this path.

The geometry ABI uses desktop bottom-left logical coordinates on macOS. Pixel crop rectangles are top-left image coordinates. Windows overlay uses virtual-desktop physical pixels and adapts top-left rectangles before calling bottom-left toolbar placement. Negative screen origins are supported by signed coordinates. Mixed-density export preserves layout at maximum participating source density.

## Smart selection boundaries
Current macOS window mode uses pre-overlay CGWindowList bounds and excludes our process. It selects visible desktop pixels in that boundary. Accessibility / UI Automation and browser DOM augmentation remain separate future services; none is required for capture. Windows window selection is still outstanding.

## Recording service, deferred
A future recording session must remain owned by the host regardless of settings / Chrome. It needs a state machine for permission, source closure, display changes, suspend, audio device changes, pause timestamp correction, finalize and failure cleanup. Screenshot rectangle UI does not implement video cropping. No current code advertises recording support.

## Chrome companion, deferred
A versioned Native Messaging adapter will accept a small allowlist of user-triggered requests. Payload lengths, request IDs, origin association and capabilities need validation. It must not expose shell execution or arbitrary file writes. The adapter is packaged with the desktop product; disconnect does not terminate the host. Browser element rectangles are hints with DPR/zoom/frame context, never trusted desktop coordinates.

## Remaining release gates
Windows compile and physical capture; multiple monitors and mixed density; actual physical feedback timing; HDR/color conversion; macOS full-screen Spaces; Windows capture exclusion and protected content; source interruption; stable signing, notarization / Windows signing; install/uninstall. The CI workflow is prepared, not executed in this local task.
