# Android Camera Controls Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the Android Coach camera the iOS #116 lens buttons, zoom dial, pinch zoom, tap to focus and saved Auto/On/Off flash.

**Architecture:** Pure zoom/lens/flash maths in `CameraControls.kt` (JVM-tested, mirrors iOS `CoachCameraControls.swift` + `CoachCameraSession` statics). Two composables (`CameraLensBar` with its dial, `CameraFlashButton`) in the same file. `CoachCameraScreen.kt` keeps the bound `Camera`, reads `cameraInfo.zoomState`, and wires pinch, tap, lens and flash to `CameraControl` / `ImageCapture`.

**Tech Stack:** Kotlin, Jetpack Compose, CameraX 1.6.2 (`camera-camera2`, `camera-lifecycle`, `camera-compose`), JUnit 4, Compose UI test.

**Spec:** `docs/superpowers/specs/2026-11-16-android-camera-controls-design.md`

## Global Constraints

- No new dependency; CameraX 1.6.2 only.
- Touch targets ≥ 48 dp; TalkBack labels "Flash" (value Auto/On/Off) and "<n> times zoom" (selected on the current lens).
- Zoom clamp: widest lens … 2 × longest lens, also within the camera's `minZoomRatio`…`maxZoomRatio`.
- Dial: 90 dp per doubling, 76 dp tall, 280 dp wide, slide threshold 10 dp, ticks every 1/10 doubling.
- Focus mark: 72 dp yellow square, fades over 1.2 s; focus auto-cancels after 5 s (CameraX default).
- Flash saved in `getSharedPreferences("mivu", MODE_PRIVATE)` key `cameraFlash`, values `ImageCapture.FLASH_MODE_*`, default AUTO.
- Snap It launch speed, timer and Duo layouts are out of scope.
- Emulator-only verification; record SHA and counts in `docs/verification/`.

## Review Focus

- Phone hides its physical lenses but its zoom range starts at 0.5: no buttons, pinch still reaches 0.5 (Task 1 `clampWithoutLensesUsesCameraRange`).
- Camera max zoom below 2 × longest lens: zoom never asks past the camera max (Task 1 `clampRespectsCameraMax`).
- Dial steps arriving quickly: each step is a ratio of the current zoom, so the result does not depend on frame timing (Task 1 `slideZoomIsRatio`).
- Font scale 2: lens labels still fit their 48 dp circles (Task 3 `lensBarFitsAtFontScale2`).
- Recreate / reopen the camera: the flash choice survives (Task 2 `flashChoiceIsRemembered`).

---

### Task 1: Lens and zoom maths

**Files:**
- Create: `android/app/src/main/java/com/yakov103/mivu/ui/coach/CameraControls.kt`
- Test: `android/app/src/test/java/com/yakov103/mivu/ui/coach/CameraControlsTest.kt`

**Interfaces:**
- Produces:
  - `fun lensZooms(intrinsicRatios: List<Float>): List<Float>` — sorted, de-duplicated to one decimal; empty when fewer than two lenses.
  - `fun clampedZoom(zoom: Float, lenses: List<Float>, min: Float, max: Float): Float`
  - `fun currentLens(zoom: Float, lenses: List<Float>): Float?` — last lens ≤ zoom + 0.01, else first.
  - `fun zoomText(zoom: Float): String` — one decimal, no ".0".
  - `fun slideZoom(zoom: Float, slidDp: Float): Float` — `zoom * 2^(-slidDp / 90)`.
  - `fun nextFlash(mode: Int): Int` — AUTO→ON→OFF→AUTO.
  - `const val DIAL_DP_PER_DOUBLING = 90f`

- [ ] **Step 1: Write the failing tests**

```kotlin
@Test fun lensesFromRatios() {
    assertEquals(listOf(0.5f, 1f, 5f), lensZooms(listOf(1f, 0.5f, 5f, 1.0001f)))
    assertEquals(emptyList<Float>(), lensZooms(listOf(1f)))
    assertEquals(emptyList<Float>(), lensZooms(emptyList()))
}
@Test fun clampToTwiceLongestLens() = assertEquals(10f, clampedZoom(30f, listOf(0.5f, 1f, 5f), 0.5f, 30f))
@Test fun clampRespectsCameraMax() = assertEquals(8f, clampedZoom(9f, listOf(0.5f, 1f, 5f), 0.5f, 8f))
@Test fun clampWithoutLensesUsesCameraRange() {
    assertEquals(0.5f, clampedZoom(0.1f, emptyList(), 0.5f, 10f))
    assertEquals(10f, clampedZoom(20f, emptyList(), 0.5f, 10f))
}
@Test fun currentLensFollowsZoom() {
    assertEquals(1f, currentLens(2.9f, listOf(0.5f, 1f, 3f)))
    assertEquals(3f, currentLens(2.995f, listOf(0.5f, 1f, 3f)))
}
@Test fun zoomLabels() { assertEquals("0.5", zoomText(0.5f)); assertEquals("3", zoomText(3.02f)); assertEquals("1.4", zoomText(1.36f)) }
@Test fun slideZoomIsRatio() {
    assertEquals(1f, slideZoom(2f, 90f), 0.001f)
    assertEquals(slideZoom(slideZoom(2f, 30f), 60f), slideZoom(2f, 90f), 0.001f)
}
@Test fun flashCycles() {
    assertEquals(ImageCapture.FLASH_MODE_ON, nextFlash(ImageCapture.FLASH_MODE_AUTO))
    assertEquals(ImageCapture.FLASH_MODE_OFF, nextFlash(ImageCapture.FLASH_MODE_ON))
    assertEquals(ImageCapture.FLASH_MODE_AUTO, nextFlash(ImageCapture.FLASH_MODE_OFF))
}
```

- [ ] **Step 2: Run, expect compile failure**

Run: `./gradlew :app:testDebugUnitTest --tests '*CameraControlsTest'`
Expected: FAIL, unresolved references.

- [ ] **Step 3: Implement the functions above in `CameraControls.kt`**

Clamp: lower bound `max(min, lenses.firstOrNull() ?: min)`, upper `min(max, lenses.lastOrNull()?.times(2) ?: max)`.

- [ ] **Step 4: Run, expect PASS (8 tests)**

- [ ] **Step 5: Commit** `feat(android): add camera lens and zoom maths`

### Task 2: Flash button with saved choice

**Files:**
- Modify: `android/app/src/main/java/com/yakov103/mivu/ui/coach/CameraControls.kt`
- Modify: `android/app/src/main/java/com/yakov103/mivu/ui/coach/CoachCameraScreen.kt` (top row, `capture`)
- Test: `android/app/src/androidTest/java/com/yakov103/mivu/ui/coach/CameraControlsUiTest.kt`

**Interfaces:**
- Consumes: `nextFlash`.
- Produces: `@Composable fun CameraFlashButton(mode: Int, onChange: (Int) -> Unit)`; icons from existing drawables or new vector drawables `ic_flash_auto`, `ic_flash_on`, `ic_flash_off` (Material Symbols); On tinted yellow.

- [ ] **Step 1: Failing Compose tests** — `flashButtonCyclesAndSpeaksMode`: button with content description "Flash" has state description "Auto"; click → "On" and `onChange(FLASH_MODE_ON)`. `flashChoiceIsRemembered` (in `CoachCameraTest`): set prefs `cameraFlash` = OFF, open camera, `capture.flashMode` reads OFF via the screen; skip with `assumeTrue` when the emulator camera reports no flash unit.
- [ ] **Step 2: Run** `./gradlew :app:connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=com.yakov103.mivu.ui.coach.CameraControlsUiTest` — expect FAIL.
- [ ] **Step 3: Implement** — button 48 dp circle on `Scrim`; in the screen, read/write `cameraFlash` in prefs `mivu`, set `capture.flashMode`, show only when `camera.cameraInfo.hasFlashUnit()`.
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** `feat(android): add a saved Auto, On, Off flash to the Coach camera`

### Task 3: Lens buttons and zoom dial

**Files:**
- Modify: `CameraControls.kt`, `CoachCameraScreen.kt` (above `ShutterBar`)
- Test: androidTest `CameraControlsUiTest.kt`

**Interfaces:**
- Consumes: `lensZooms`, `currentLens`, `zoomText`, `slideZoom`, `DIAL_DP_PER_DOUBLING`.
- Produces: `@Composable fun CameraLensBar(zoom: Float, lenses: List<Float>, onZoom: (Float) -> Unit, onZoomBy: (Float) -> Unit)` where `onZoomBy` takes a ratio.

- [ ] **Step 1: Failing Compose tests** with synthetic lenses `[0.5, 1, 3]`, zoom 1.4: three buttons "0.5 times zoom", "1 times zoom", "3 times zoom"; "1 times zoom" is selected and shows "1.4×"; click "3 times zoom" → `onZoom(3f)`; `lensBarHiddenForOneLens` with `[]`; horizontal swipe of 90 dp on the bar → product of `onZoomBy` ratios ≈ 0.5; `lensBarFitsAtFontScale2` — each button's text is not clipped (bounds within 48 dp).
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement** — `Row` of 48 dp circles; `pointerInput` drag with 10 dp slop shows the dial (Compose `Canvas`, iOS geometry: radius 300, top 26, ticks 6/12 dp, labels on lenses, yellow needle and "n×"), hidden from accessibility; `HapticFeedbackType.SegmentTick` when `currentLens` changes; fade 150/300 ms skipped when animations are off (`MotionPolicy`). In the screen, lenses = `lensZooms(camera.cameraInfo.physicalCameraInfos.map { it.intrinsicZoomRatio })`; zoom from `cameraInfo.zoomState`; `onZoom`/`onZoomBy` call `cameraControl.setZoomRatio(clampedZoom(...))`.
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** `feat(android): add lens buttons and a zoom dial to the Coach camera`

### Task 4: Pinch zoom and tap to focus

**Files:**
- Modify: `CoachCameraScreen.kt` (viewfinder)
- Test: androidTest `CoachCameraTest.kt`

**Interfaces:**
- Consumes: `clampedZoom`.
- Produces: none.

- [ ] **Step 1: Failing emulator tests** — `pinchChangesZoom`: pinch out on the viewfinder; `zoomState.value.zoomRatio` rises above 1 (assume the emulator camera's max > 1). `tapShowsFocusMark`: tap the viewfinder; a node tagged `cameraFocusMark` appears.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement** — `CameraXViewfinder(coordinateTransformer = MutableCoordinateTransformer())`; `pointerInput` `detectTransformGestures` → `onZoomBy(zoomChange)`; `detectTapGestures` → transform tap to surface coords, `SurfaceOrientedMeteringPointFactory(resolution.width, resolution.height).createPoint(x, y)`, `cameraControl.startFocusAndMetering(FocusMeteringAction.Builder(point).build())`; draw the 72 dp mark at the tap, fade 1.2 s.
- [ ] **Step 4: Run, expect PASS; rerun the existing `CoachCameraTest` suite (capture/close/retake unchanged).**
- [ ] **Step 5: Commit** `feat(android): pinch to zoom and tap to focus in the Coach camera`

### Task 5: Evidence and parity

**Files:**
- Create: `docs/verification/2026-11-16-android-camera-controls.md`
- Modify: `docs/parity.md` row `camera-controls`, `android/CHANGELOG.md` only if the release tooling expects it (it is automated; leave alone otherwise)

- [ ] **Step 1:** Record source SHA, emulator image/API, results for `CameraControlsTest` (JVM + androidTest) and `CoachCameraTest`; mark lenses/focus/flash on a physical phone `blocked`.
- [ ] **Step 2:** Parity row Android → `partial` with the record and named tests; note no real-device check.
- [ ] **Step 3:** `python3 scripts/ci/parity.py` passes.
- [ ] **Step 4: Commit** `docs: record Android camera controls evidence`
