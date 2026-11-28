# Android camera controls verification

Recorded 2026-11-17. Design: [Android camera controls](../superpowers/specs/2026-11-16-android-camera-controls-design.md).

- Source SHA tested: `acf883c94e154743206a21d5eb028c28dabe87bb`
- Host: Linux 7.0.0-42, JDK 21.0.13, Gradle wrapper, CameraX 1.6.2.
- Emulator: Android Emulator 36.3.10 (build 14472402), AVD `mivu_camera_api35`
  (pixel_8, Google APIs x86_64, API 35, `google/sdk_gphone64_x86_64/emu64xa:15/AE3A.240806.043`),
  `-gpu host`, emulated back camera.

## Results

| Suite | Command | Result |
|---|---|---|
| JVM unit | `./gradlew :app:testDebugUnitTest --tests 'com.yakov103.mivu.ui.coach.CameraControlsTest'` | 8 tests, 0 failed |
| Instrumented | `connectedDebugAndroidTest` with `class=com.yakov103.mivu.ui.coach.CameraControlsUiTest` | 6 tests, 0 failed, 0 skipped |
| Instrumented | `connectedDebugAndroidTest` with `class=com.yakov103.mivu.ui.coach.CoachCameraTest` | 9 tests, 0 failed, 0 skipped |

Counts come from the JUnit result XML. `CoachCameraTest` includes the new
`pinchZoomsTheViewfinder` and `tapShowsTheFocusMark`; the pinch test was not skipped,
so the emulated camera reported a zoom range above 1.05.

## Emulator note

Emulator 37.2.13 with the API 37.0 and 36.1 images crash-loops SurfaceFlinger
(`Assertion failed: !rcEnc->featureInfo()->hasReadColorBufferDma` in `RegionSampling`) with
software and host GPU modes, so no tests could run there. Emulator 36.3.10 did not bring adb
online with those images. The API 35 image above was stable.

## Blocked

- Physical phone: real lenses, focus, flash firing and pinch on hardware are `blocked`.
  Emulator results do not prove camera behaviour.
- Snap It camera-at-launch: not ported in this change.
