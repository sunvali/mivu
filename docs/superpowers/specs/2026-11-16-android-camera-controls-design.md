# Android camera controls

Parity row: `camera-controls`. iOS source of truth: #116 (`1d73ba1`),
`ios/Mivu/Coach/CoachCameraControls.swift`, `CoachCameraSession.swift`,
`CoachCameraPreview.swift`, `CoachCameraView.swift`.

## Why

iOS is the behavior source of truth. Its Coach camera gained lens buttons,
pinch zoom, a zoom dial, tap to focus and a saved flash choice; Android's
`CoachCameraScreen.kt` has only the shutter, Choose photos, Close and the photo
count. Reading a plate or a label often needs zoom, focus or flash.

## Goals

In the Android Coach camera (also what Snap It opens):

- **Lens buttons**: one 48 dp circular button per back lens, labelled by its
  zoom (`0.5`, `1`, `3`), above the shutter row. The lens in use shows the live
  zoom (`1.4×`) in yellow and is selected for TalkBack; each is labelled
  "<n> times zoom". Hidden when the phone reports one lens or fewer.
- **Zoom dial**: sliding a finger along the lens buttons (past 10 dp) shows
  the iOS arc of ticks above them and zooms; each doubling is the same distance
  (90 dp). It fades out on release. A still finger is a tap on a lens. Haptic
  tick when the current lens changes.
- **Pinch zoom** on the preview, between the widest lens and twice the longest
  lens (iOS `clampedZoom`), within the camera's reported range.
- **Tap to focus**: a tap on the preview focuses and meters there, with a
  72 dp yellow square that fades over 1.2 s. Returns to automatic after
  5 seconds (CameraX's default auto-cancel).
- **Flash**: Auto / On / Off button in the top row, only when the camera has a
  flash. Cycles Auto → On → Off. Labelled "Flash", value the mode name. The
  choice is saved and applied to `ImageCapture.flashMode`. Default Auto.

## Non-goals

- Faster Snap It launch (camera shown while the diary loads): later PR.
- iOS's 3-second timer and the Duo table layout.
- Any change to capture, draft, permission or the photo count.

## Constraints

- CameraX 1.6.2 only; no new dependency (Ponytail).
- Emulator-only verification for now (owner, 2026-11-16). Lenses, focus and
  flash stay unverified on hardware, so the row stays `partial`.
- 48 dp touch targets, TalkBack labels, reduced motion respected for the dial
  fade, English-only strings matching iOS.

## Approaches

- **A. CameraX only (chosen)**: lenses from
  `CameraInfo.physicalCameraInfos` → `intrinsicZoomRatio`, sorted and
  de-duplicated; zoom with `CameraControl.setZoomRatio`; focus with
  `FocusMeteringAction`; flash with `ImageCapture.flashMode`. Phones that hide
  physical lenses get no buttons but keep pinch over the full zoom range.
- B. CameraX plus Camera2 focal lengths: covers a few more phones that hide
  lenses, but more code and focal-length math that needs real hardware.
- C. One binding per physical lens: exact lenses but the preview blinks on
  each switch and pinch cannot cross lenses. Rejected.

## Decided

- Approach A; focus resets after 5 s; dial included now; Snap It speed later;
  emulator only (owner, 2026-11-16).

## Builder's calls

- Pure lens/zoom maths (lens list from ratios, clamping, label text, dial
  step) in a small testable file beside `CoachCameraScreen.kt`, mirroring iOS
  `CoachCameraControls.swift`. JVM unit tests use synthetic ratios.
- Flash choice in the app's existing `SharedPreferences`, key
  `cameraFlash`.
- When physical-lens info is empty and the zoom range starts below 1, no
  buttons are shown (matches "buttons come from what the phone reports").
- Docs: update `docs/parity.md` `camera-controls` and add a
  `docs/verification/` record with the tested SHA and emulator results.
