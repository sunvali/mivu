# Android Coach Screens and Animated Pip Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Coach placeholder with the real Coach tab, the same as
iOS. It has the timeline (with receipts, Undo, chips, activity and Jump to
latest), the composer (text, Photo Picker, camera, voice, drafts and Ask Pip
quotes), and an animated Pip drawn from the shared rig.

**Architecture:** This is milestone 4b, and it closes milestone 4. It builds on
the 4a engine (`CoachEngine`, `CoachWorker`, `CoachContext`, `CoachWrites`).
The owner moved the Pip renderer forward from milestone 7. It comes first,
because the Coach screen mounts it.

Pip is drawn natively. A pure-Kotlin scene turns `pip-rig.json` and a pose into
an ordered list of path draws, each with a 2D matrix. A Compose `Canvas` draws
that list. A spring layer animates each part's joint components with Compose
`SpringSpec`, using the same constants as iOS `CASpringAnimation`.

Gestures stay iOS data. An iOS test-only fixture exports
`PipGestureLibrary.all` to `fixtures/pip/gestures.json`, and Android ships that
file as an asset. Neither the rig nor the gestures is ever copied or edited by
hand.

The Coach UI lives in `com.yakov103.mivu.ui.coach`. Pip lives in
`com.yakov103.mivu.pip`. One activity-scoped `CoachViewModel` per profile keeps
the 100-exchange window, the draft and the Pip presentation across tab switches.

**Tech Stack:** Kotlin, Jetpack Compose (Material 3, `LazyColumn`, `Canvas`,
`animation-core` `SpringSpec`), coroutines, kotlinx.serialization, and the
platform SQLite store. Capture uses the system Photo Picker
(`PickMultipleVisualMedia`), CameraX (`camera-camera2`, `camera-lifecycle`,
`camera-compose`) and the platform `SpeechRecognizer`. Tests are JUnit (JVM),
Compose UI instrumented tests, and one iOS Swift Testing fixture test.

**Spec:** [`docs/superpowers/specs/2026-10-23-android-app-design.md`](../specs/2026-10-23-android-app-design.md)
(Pip, Coach rows, Android quality rules), the
[Coach behaviour contract](../../development/coach-chat-behavior.md), the
AGENTS.md "Coach chat history" rules,
[MOTION.md](../../../design-system/mivu/characters/pip/MOTION.md), the
[mivu-animation skill](../../../.agents/skills/mivu-animation/SKILL.md), and the
owner-approved mockup
[android-coach-mockups.png](../../verification/android-design/android-coach-mockups.png).
Carried items come from [`android-carried-items.md`](android-carried-items.md)
(milestone 4).

**Copy source:** `origin/main` (`e5049c32`, fetched 2026-10-24) has no diff from
this worktree under `ios/Mivu/Coach`, `ios/Mivu/Design` or
`ios/Mivu/Resources/Characters`. Every string here comes from this worktree's
iOS files, with "iPhone" replaced by "phone".

**Left for 4c (not in this plan):**
- the chat history screen and its toolbar button, including the named paging
  accessibility actions;
- seek: tapping a sent quote opens the original message, and a meal's "View
  conversation";
- reply notifications;
- long-press Reply/Copy, swipe-to-reply, and the photo Retake menu.

## Global Constraints

- **Platform:** minSdk 31. Use platform APIs first. CameraX is the only new
  dependency family. It is justified because the approved mockup needs an
  in-app full-screen preview with "Choose photos" and an "n of 8 photos" count
  that stays open across shots. The system `TakePicture` intent returns after
  each shot, and its UI varies by device. Pin one stable CameraX version
  through a single `version.ref`.
- **iOS is the authority** for limits, copy, timings and state rules. Coach
  limits:
  - 20 exchanges per page, at most 5 pages and 100 exchanges, counting
    resident, reserved and retired page work;
  - at most 8 draft attachments and 20,000 characters of text;
  - at most 2 concurrent photo decodes and a 16 MiB decoded-photo cache;
  - reply excerpts of at most 280 characters.
- **Jump to latest:**
  - a 48 dp circle with the down-arrow icon and the spoken label "Jump to latest";
  - a touch target of at least 48 dp;
  - it never takes focus or reader position from the underlying exchange;
  - a drag that starts on it scrolls the timeline;
  - after paging or appends, the reader's position is restored within 2 dp.
- **Touch targets:** at least 48 dp, the Android standard (spec), for chips,
  Undo, Review / Edit, Cancel reply, Remove/Keep and Retry.
- **Rig:**
  - `ios/Mivu/Resources/Characters/pip/pip-rig.json` is read in place as an
    Android asset (`pip/pip-rig.json`);
  - the loader rejects more than 1,048,576 bytes, any version other than 2,
    and any path command other than absolute `M L C Q Z`;
  - every head view (`right`, `front`, `left`) must have `head`, `eye-l.open`,
    `eye-r.open` and `mouth.closedSmile`.
- **Pip sizes and crops:**
  - Coach: 112 dp wide (76 dp when `isLargeText()`), cropped to the rig's
    `coach` frame, seated set;
  - Today: the existing 186/144 dp cookie backdrop, `today` frame, standing set.
- **Motion constants** (iOS `PipRigView` and `MivuMotion`):
  - joint springs: ω = clamp(3.76 / max(period, 0.05), 14, 60), stiffness ω²,
    mass 1, damping ratio 0.68;
  - followers (`ear-`, `tail-2/3/4`, `scarf-end-`, `forearm-`, `paw-`): ω × √0.6,
    damping ratio 0.5, starting 60 ms late;
  - gaze parts: ω 110, damping ratio 0.6;
  - eyes lead a head turn by 80 ms;
  - blink: 160 ms, key times 0/0.25/0.7/0.95/1; a double blink adds a second
    at +300 ms;
  - breathing: head and chest scale Y +2% over 4.5 s, ease-in-out, reversing;
  - opacity fade 180 ms; heart pop from scale 0.2, stiffness 260, damping
    ratio 9/(2√260);
  - `MivuMotion`: greeting 0.9 s, submitted 0.8, saved 0.45, curious 1.0,
    tapped 0.8, patted 1.3, feedbackLifetime 10 s; the other constants are
    ported verbatim.
- **Motion policy** (iOS `MotionPolicy` and the skill):
  - the system "Remove animations" setting (`!ValueAnimator.areAnimatorsEnabled()`),
    Power Saver (`PowerManager.isPowerSaveMode`) or a thermal status of
    `THERMAL_STATUS_SEVERE` or higher gives the static pose: zero coroutines,
    zero frame callbacks, and the idle scheduler stopped;
  - a lifecycle owner below `RESUMED` (another tab, a pushed or dialog route,
    the picker or camera covering it, or the app in the background) gives
    `hidden`, which is also zero work.
- **Pip behaviour:**
  - Pip is cleared from semantics (`clearAndSetSemantics {}`); native text
    carries status, and tap and pat are decorative;
  - never celebrate or comment on food amounts: events carry only their kind
    (saved, photo added) and never a quantity;
  - no confetti, points or streaks; recovery is never cheerful.
- **Capture:**
  - Coach capture goes through `captureCoachSubmission`. An uncertain save
    reconciles the same immutable payload (`reconcileCoachCapture`) before it
    retries or clears the draft;
  - capturing or picking a photo never sends;
  - an unsent draft is not a durable queue, but it survives rotation through
    `SavedStateHandle`, like `MealComposerViewModel`.
- **Bounded reads:** Coach reads only bounded queries (`LIMIT`) and never calls
  `snapshot()`; `snapshotReads` stays 0.
- **Data and logs:** synthetic data only, in tests and fixtures. Never log
  prompts, replies, tokens or transcripts.
- **Speed:** each task runs only its own test classes, one class per
  `connectedDebugAndroidTest` run (a comma list runs only the first). The full
  suite runs once, in Task 9.

  ```sh
  cd android
  ./gradlew :app:testDebugUnitTest --tests '*<Class>'
  ./gradlew :app:connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=com.yakov103.mivu.<pkg>.<Class>
  ```

## Review Focus

1. **"Remove animations", Power Saver or a thermal spike flips while Pip is
   mid-gesture**: Pip snaps to the moment's still pose. No coroutine, frame
   loop or idle timer is left running, and turning the setting off resumes
   from rest. (Task 3: `policyFlipMidGestureLeavesZeroJobs`)
2. **The process dies or the save throws after the commit, and the person taps
   Send again**: the same submission is reconciled. There is no second turn,
   and the draft clears once. (Task 6: `uncertainSaveReconcilesWithoutDuplicate`)
3. **The reader is scrolled back when a reply or new turn lands**: the visible
   row stays within 2 dp, Jump to latest appears, and focus stays where it
   was. (Task 5: `replyWhileBrowsingKeepsPositionWithin2dp`)
4. **A diary with 10,000 turns**: Coach opens on the latest page with bounded
   reads. Scrolling back never holds more than 100 exchanges, counting
   in-flight reads, and `snapshotReads` stays 0. (Task 4:
   `tenThousandTurnsStayBounded`)
5. **Camera permission denied or permanently denied, or the activity is
   recreated mid-capture**: the composer text and photos are intact.
   "Allow camera access in Settings, or choose photos." offers Open Settings
   and Choose photos. (Task 7: `deniedKeepsDraftAndOffersChoosePhotos`)

---

### Task 1: Pip rig loader, scene and renderer

**Files:**
- Modify: `android/app/build.gradle.kts`. Add
  `sourceSets.getByName("main").assets.srcDir("../../ios/Mivu/Resources/Characters")`
  and the same directory to the `test` resources, so JVM tests read
  `pip/pip-rig.json`.
- Create:
  - `android/app/src/main/java/com/yakov103/mivu/pip/PipRigAsset.kt`
  - `pip/PipPose.kt`
  - `pip/PipRigScene.kt`
  - `pip/PipRig.kt`
- Create: `android/app/src/debug/java/com/yakov103/mivu/PipRigPreviewActivity.kt`
  and its entry in the debug `AndroidManifest.xml`.
- Test: `android/app/src/test/java/com/yakov103/mivu/pip/PipRigAssetTest.kt`, `PipRigSceneTest.kt`

**Interfaces:**
- Produces:
  - `@Serializable data class PipRigAsset(version: Int, artboard: Float, ground: Float, parallaxScale: Float = 0f, frames: Map<String, List<Float>>, parts: List<Part>)`,
    with `Part(id, parent?, pivot: List<Float>, z: Int, set?, view?, shape?, visible, parallax?, fill, fillDark?, path, mount: List<Float>?)`
    and `val Part.name` (the id without its `@view` suffix).
  - `fun PipRigAsset.Companion.load(bytes: ByteArray): PipRigAsset`, which
    throws `PipRigError.TooLarge | Version | MissingPart(id) | BadPath(path)`.
  - `fun parsePath(svg: String): List<PathOp>`, with
    `sealed interface PathOp { MoveTo(x,y); LineTo(x,y); CubicTo(x1,y1,x2,y2,x,y); QuadTo(x1,y1,x,y); Close }`.
    The separators `, \n\t` are skipped, as in iOS `cgPath`.
  - `data class PipPose(joints: Map<String, Joint> = emptyMap(), eyes: EyeShape = open, mouth: MouthShape = closedSmile, gazeX: Float = 0f, gazeY: Float = 0f, blush: Boolean = false, hearts: Int = 0, set: BodySet = standing, headTurn: Float = 1f)`.
    `Joint(rotation: Float /*rad*/, offsetX, offsetY, scaleX = 1f, scaleY = 1f)`.
    The enums use the iOS raw names.
  - `class PipRigScene(asset: PipRigAsset, bounds: (partID: String) -> FloatArray /*minX,minY,maxX,maxY*/)`:
    - `fun resolve(pose: PipPose): PipResolved`. It returns each part's joint,
      with gaze reach, glint counter-shift and parallax applied, plus the
      visible set, each part's alpha and the body set.
    - `fun draw(state: PipResolved, scaleYAdd: Map<String, Float> = emptyMap()): List<PipDraw>`.
  - `data class PipDraw(partID: String, matrix: FloatArray /*a,b,c,d,tx,ty, artboard space*/, fill: String, fillDark: String?, alpha: Float, clip: PipDraw?)`.
  - `@Composable fun PipRig(scene: PipRigScene, state: () -> PipResolved, dark: Boolean, frame: String?, modifier: Modifier)`.
    It reads `state` in the draw phase only, so frames never recompose. It
    caches one `Path` per part from `PathOp`, fits `asset.frames[frame]` into
    the size, and crops the bottom edge only.
- **Port rules** (iOS `PipRigView.build`, `apply` and `joint(of:)`; these
  decide what the tests check):
  - **Tree:** a part hangs under its `parent`, or under the root if it has
    none. A part on `body` with `set == null` rides the head mount. The head
    mount sits on the active set's `body`, transformed by that body's `mount`
    `[k, tx, ty]` (point × k + t). Its z is the lowest z of the parts that
    ride it.
  - **Draw order:** within a node, the node's own shape (at its z) and its
    child nodes (each at its own z) are drawn in ascending z. Recurse in that
    order.
  - **Matrix:** a part's local transform about its pivot p is
    `p' = pivot + offset + S·R·(p − pivot)`. That is iOS
    `Scale·Rotate` concatenated with `Translate(offset)`, rotation positive
    clockwise in y-down. The world matrix is parent × local.
  - **Visibility** (iOS `isShown`):
    - the view must match the active head view and the set must match;
    - a part with a `shape` slot shows only when it is the wanted
      `eye-l.<eyes>`, `eye-r.<eyes>` or `mouth.<mouth>` slot (a slot is
      inherited from the nearest ancestor that has one);
    - other parts show when `visible`, or when they are blush or hearts.
  - **Head view** from `headTurn`: above 0.35 is right (centre 1, span 0.65);
    below -0.35 is left (centre -1, span 0.65); otherwise front (span 0.35).
    The slide is clamped to ±1. Parallax x = `parallax × slide × parallaxScale`.
  - **Gaze:**
    - gaze is clamped to the unit disc;
    - an iris travels 0.3 × the eye white's width by 0.4 × its height, and is
      clipped to the eye-white path;
    - a pupil travels up to 35% of the iris radius, never past the iris edge;
    - a glint counter-shifts by 0.3 × the iris reach.
  - **Alpha:** `cheek-blush*` is 1 when `blush`; `heart-n` is 1 when
    `n <= hearts`. Progress props are out of scope.
  - **Fill:** `fillDark ?: fill` in dark mode.
- **Debug preview:** shows the rest pose (standing and seated) at 40, 64, 88
  and 200 dp in light and dark. Launch it with
  `adb shell am start -n com.yakov103.mivu/.PipRigPreviewActivity`.

- [ ] **Step 1: Failing tests.**
  - In `PipRigAssetTest`:
    - `shippedRigLoads`: version 2, `frames["coach"] == [37.3, 29.2, 277.8, 288.8]`,
      and every path parses;
    - `oversizeRejected`: 1,048,577 bytes give `TooLarge`;
    - `wrongVersionRejected`;
    - `missingHeadViewRejected`: removing `mouth.closedSmile@left` gives
      `MissingPart("mouth.closedSmile@left")`;
    - `relativePathRejected`: `"M 0 0 l 1 1"` gives `BadPath`.
  - In `PipRigSceneTest`, which uses the shipped rig and fake bounds:
    - `restSeatedShowsOnlySeatedSetAndRightView`;
    - `drawOrderFollowsTreeThenZ`: a `data-parent` part with a lower z is
      drawn before its parent's shape;
    - `jointMatrixRotatesScalesThenOffsets`: pivot (10,10), rotation 90°,
      scale (2,1), offset (5,0) map the point (11,10) to (15,11);
    - `headTurnPicksView`: 0.2 is front, 0.5 is right, -0.5 is left;
    - `gazeMovesIrisByReachAndClips`;
    - `blushAndHeartsUseAlpha`;
    - `headMountFollowsActiveBody`.
- [ ] **Step 2: Run** `--tests '*PipRigAssetTest'` and `--tests '*PipRigSceneTest'`.
  Expected: FAIL (unresolved references).
- [ ] **Step 3: Implement** the files above and the debug preview.
- [ ] **Step 4: Run** both classes. Expected: PASS. Install the debug build,
  launch the preview, and check that seated and standing Pip match
  `design-system/mivu/characters/pip/reference.png` at 88 and 200 dp in light
  and dark.
- [ ] **Step 5: Commit**

```bash
git add android/app/build.gradle.kts android/app/src/main/java/com/yakov103/mivu/pip android/app/src/debug android/app/src/test/java/com/yakov103/mivu/pip
git commit -m "feat(android): draw Pip from the shared rig"
```

### Task 2: Gestures, springs and idle beats

**Files:**
- Create: `ios/MivuTests/PipGestureFixtureTests.swift`. This is an iOS
  test-only change, following the pattern of `CoachToolsFixtureTests`. With
  `MIVU_WRITE_FIXTURES=1` it writes `fixtures/pip/gestures.json`; otherwise it
  expects that file to equal the current library.
- Create: `fixtures/pip/gestures.json` (generated; never hand-edited).
- Modify: `android/app/build.gradle.kts`. Add `assets.srcDir("../../fixtures/pip")`
  (the app reads asset `gestures.json`; JVM tests read `pip/gestures.json`)
  to main. Test resources already include `fixtures`.
- Create:
  - `android/app/src/main/java/com/yakov103/mivu/pip/PipGestures.kt`
  - `pip/PipIdleScheduler.kt`
  - `pip/PipMotion.kt`
  - `pip/MivuMotion.kt`
- Modify: `PipRigPreviewActivity.kt` (adds a button for every gesture,
  blinking and glances).
- Test: `android/app/src/test/java/com/yakov103/mivu/pip/PipGestureLibraryTest.kt`, `PipMotionTest.kt`, `PipIdleSchedulerTest.kt`

**Interfaces:**
- Consumes: `PipPose`, `PipRigScene.resolve/draw` and `PipResolved` from
  Task 1.
- Produces:
  - **`gestures.json`**, with sorted keys:
    - `{"generatedBy": "ios/MivuTests/PipGestureFixtureTests.swift", "gestures": [...], "moments": {...}}`;
    - each gesture is `{name, loops, endSet?, keys: [{at, pose}]}`, and each
      pose is `{joints: {name: {rotation, offset: [x,y], scale: [w,h]}}, eyes, mouth, gaze: [x,y], blush, hearts, set, headTurn}`;
    - `moments` maps every `PipMoment` value to its gesture name (from
      `gesture(for:)`). That covers greeting hours 0–23, tapped levels 0–4,
      progressTap levels 0–5, and every other case once. Keys look like
      `"greeting:7"`, `"tapped:4"` and `"saved"`.
  - `data class PipGesture(name: String, keys: List<Pair<Double, PipPose>>, loops: Boolean, endSet: BodySet?)`,
    with `val duration`.
  - `sealed interface PipMoment`, with every iOS case and its iOS arguments.
  - `object MivuMotion` (in `pip/MivuMotion.kt`), with every iOS constant
    verbatim, and `enum CompanionSurface { Today, Coach }`.
  - `class PipGestureLibrary(gestures: List<PipGesture>)`:
    - `companion fun load(json: String)`;
    - `fun named(name)`;
    - `fun gesture(moment: PipMoment)`, a Kotlin port of the iOS switch;
    - `fun loop(moment): PipGesture?`;
    - `fun stillPose(moment): PipPose`, the key before the final settle;
    - `fun gesture(idle: PipIdleScheduler.Beat, curled: Boolean): PipGesture?`.
  - `class PipIdleScheduler(random: kotlin.random.Random)`, with
    `fun next(lastInput: Long, now: Long, surface: CompanionSurface): Pair<Beat, Long /*at ms*/>`.
    It is a one-to-one port: 2–6 s ahead; yawn and stretch after 30 s quiet;
    on Today, hug the tail after 90 s and then curl up; Coach never curls; a
    curled Pip only blinks and flicks an ear; never the same beat kind twice.
  - `class PipMotion(scene: PipRigScene)`:
    - `fun transition(target: PipPose, periodSeconds: Double, nowNanos: Long)`
      adds one Compose `SpringSpec` per changed joint component (rotation,
      x, y, scaleX, scaleY). It starts from the sampled value and velocity,
      so any gesture interrupts any other without a jump. A part that was
      hidden snaps. Opacity fades linearly over 180 ms, and hearts pop.
    - `fun apply(pose: PipPose)` snaps with no animation.
    - `fun blink(double: Boolean, nowNanos)`.
    - `fun setBreathing(on: Boolean)`.
    - `fun sample(nowNanos: Long): List<PipDraw>`.
    - `val pose: PipPose`.
  - `class PipPlayer(scope: CoroutineScope, motion: PipMotion, nanos: () -> Long)`:
    - `fun play(gesture: PipGesture, onDone: (finished: Boolean) -> Unit)`,
      ported from iOS `schedule` and `step`: a key's spring launches at the
      previous key's time; eyes lead a head turn by 80 ms; a view swap lands
      inside a blink; loops repeat;
    - `fun look(x: Float, y: Float)`: a 0.06 s saccade, then after 0.1 s the
      head follows over 0.45 s (`headTurn = 1 + 0.35x`, nod 3° × y unless
      already nodding);
    - `fun stop()`;
    - `val pendingJobs: Int`.

- [ ] **Step 1: Generate the fixture.** Write `PipGestureFixtureTests`, run
  it with `MIVU_WRITE_FIXTURES=1` through XcodeBuildMCP (suite selector
  `-only-testing:MivuTests/PipGestureFixtureTests`), then run it again
  without the variable. Expected: PASS with 1 test. Record the simulator and
  the count for Task 9.
- [ ] **Step 2: Failing Android tests.**
  - In `PipGestureLibraryTest`, ported from iOS `PipGestureTests` and run
    over the fixture:
    - `everyOneShotEndsAtRestWithinTwoSeconds`;
    - `onlyCurlUpAndWakeChangeBodySet`;
    - `squashStaysWithinTenPercent`;
    - `everyJointNamesARigPart`;
    - `momentMappingMatchesIosTable`, which checks every `moments` entry
      against `gesture(moment)`;
    - `stillPoseIsKeyBeforeSettle`;
    - `durationsCoverGestures`: every `MivuMotion` reaction lasts at least its
      gesture, and within 0.3 s of it.
  - In `PipMotionTest`:
    - `springUsesCoreAnimationConstants`: a 0.45 s period gives ω 14,
      stiffness 196 and damping ratio 0.68, and a follower gives ω 14√0.6 and
      damping ratio 0.5;
    - `followerStartsSixtyMsLate`;
    - `retargetStartsFromSampledValue`;
    - `hiddenPartSnaps`;
    - `blinkShowsHalfShutHalfOpenOver160ms`;
    - `breathingAddsTwoPercentAtPeak`.
  - Player tests, using `TestScope`:
    - `playLaunchesKeysAtPreviousKeyTime`;
    - `newPlayInterruptsAndReportsFalse`;
    - `loopRepeatsFromFirstKey`;
    - `stopLeavesZeroPendingJobs`.
  - In `PipIdleSchedulerTest`:
    - `neverSameKindTwice`;
    - `yawnNeedsThirtySecondsQuiet`;
    - `coachNeverCurls`;
    - `beatIsTwoToSixSecondsAhead`;
    - `curledOnlyBlinksAndFlicks`.
- [ ] **Step 3: Run** the three classes. Expected: FAIL.
- [ ] **Step 4: Implement.**
- [ ] **Step 5: Run** the three classes. Expected: PASS. Watch every gesture
  in the preview at original speed at 88 dp: onsets, peaks and settles, feet
  back on the ground line, and the seated set in Coach.
- [ ] **Step 6: Commit**

```bash
git add ios/MivuTests/PipGestureFixtureTests.swift fixtures/pip android/app/build.gradle.kts android/app/src/main/java/com/yakov103/mivu/pip android/app/src/debug android/app/src/test/java/com/yakov103/mivu/pip
git commit -m "feat(android): animate Pip with the iOS gestures and springs"
```

### Task 3: Companion presentation, runtime, motion policy, and Pip on Today

**Files:**
- Create:
  - `android/app/src/main/java/com/yakov103/mivu/pip/MotionPolicy.kt`
  - `pip/CompanionPresentation.kt`
  - `pip/CompanionRuntime.kt`
  - `pip/PipCompanion.kt`
- Modify: `android/app/src/main/java/com/yakov103/mivu/ui/today/TodayScreen.kt`.
  Its `Pip(size)` draws `PipCompanion` on the existing backdrop instead of
  `R.drawable.pip_preview`.
- Test: `android/app/src/test/java/com/yakov103/mivu/pip/MotionPolicyTest.kt`, `CompanionPresentationTest.kt`, `CompanionRuntimeTest.kt` (JVM); `android/app/src/androidTest/java/com/yakov103/mivu/pip/PipCompanionTest.kt`

**Interfaces:**
- Consumes: `PipGestureLibrary`, `PipMotion`, `PipPlayer`,
  `PipIdleScheduler`, `MivuMotion` and `CompanionSurface` from Task 2.
- Produces:
  - `object MotionPolicy`, with
    `enum Playback { Hidden, StaticPose, Animated }` and
    `fun playback(removeAnimations: Boolean, powerSave: Boolean, thermalStatus: Int, resumed: Boolean): Playback`.
  - `@Composable fun rememberMotionPlayback(): Playback`. It reads
    `ValueAnimator.areAnimatorsEnabled()` (re-read through a `ContentObserver`
    on `Settings.Global.ANIMATOR_DURATION_SCALE`), Power Saver (through
    `ACTION_POWER_SAVE_MODE_CHANGED`), thermal status (through
    `addThermalStatusListener`), and whether `LocalLifecycleOwner` is
    `RESUMED`.
  - `enum CompanionPose { Resting, Attentive, Thinking, Saved, Recovery, Greeting, Submitted, Curious, Tapped, Patted }`.
    These are the Coach and Today poses. Reviewed, welcome back, first meal,
    day complete and the Progress poses wait for milestone 7.
  - `CompanionEvent(profileID, operationID, kind: Saved | PhotoAdded, committedAt)`
    and `CompanionSubmission(profileID, operationID, acceptedAt, attemptID)`.
  - `CompanionContext(surface?, isTyping, isProcessing, needsRecovery, playback, draftLength)`
    and `CompanionOutput(pose, playback, reactionID?, tapLevel, typingProgress)`.
  - `class CompanionPresentation(nowMs: () -> Long)`, a one-to-one port of the
    iOS class for those poses:
    - `attach(profileID)`;
    - `receive(submission)` and `receive(event)`, deduplicated by
      profile/operation(/attempt) and dropped after 10 s or when older than
      the attach or the latest commit;
    - `resolve(context): CompanionOutput`, with the iOS priority order
      (policy > recovery > typing > fresh success > processing > tap/pat >
      greeting > rest);
    - `touch(kind): Boolean`, where a rapid burst ends in a shake-off at the
      fifth tap within 1.5 s each.
  - `class CompanionRuntime(library, scene, scope, nowMs, random)`, ported
    from iOS `apply`, `showStill`, `earTwitch`, `stop` and the idle loop:
    - `fun apply(output: CompanionOutput, surface: CompanionSurface)`;
    - `fun earTwitch()`;
    - `fun stop()`;
    - `val motion: PipMotion`;
    - `val activeJobs: Int`.

    Under `StaticPose` or `Hidden` it cancels the idle loop, the player and
    breathing, and applies `stillPose(moment)` with Coach seated. Typing gaze
    is `(-0.3 + 1.3·progress, 0.8)`, holding the attentive first key with a
    14° nod and `headTurn = 1 + 0.35x`.
  - `@Composable fun PipCompanion(output: CompanionOutput, surface: CompanionSurface, size: Dp, runtime: CompanionRuntime, onTouch: (CompanionTouch) -> Unit, modifier: Modifier = Modifier)`:
    - the frame is `size` wide with the crop's aspect for Coach (height
      rounded to whole dp), and `size` tall for Today;
    - it runs a `withFrameNanos` loop only while animated;
    - taps and long-presses (`detectTapGestures`, long press counts as a pat)
      only while animated, with `LocalHapticFeedback`;
    - it is marked `testTag("pipCompanion")` and then `clearAndSetSemantics {}`.
  - `object PipAssets`, with `suspend fun load(context): Pair<PipRigScene, PipGestureLibrary>`.
    It loads once per process on `Dispatchers.IO`, using
    `android.graphics.Path.computeBounds` for the scene's bounds.

- [ ] **Step 1: Failing tests.**
  - In `MotionPolicyTest`:
    - `notResumedIsHidden`;
    - `removeAnimationsIsStatic`;
    - `powerSaveIsStatic`;
    - `severeThermalIsStatic`, where moderate thermal stays animated;
    - `otherwiseAnimated`.
  - In `CompanionPresentationTest`, ported from the iOS cases for these poses:
    - `submittedThenSavedThenRest`;
    - `typingClearsReactions`;
    - `recoveryOutranksEverything`;
    - `processingShowsThinkingAfterSubmitted`;
    - `staleEventIgnored`;
    - `duplicateEventIgnored`;
    - `tapDuringProcessingOnlyTwitches`;
    - `fifthRapidTapShakesOff`;
    - `greetingOnceAfterAttach`;
    - `savedEventCarriesNoAmount`, which checks that no `CompanionEvent` field
      holds a quantity, so food amounts cannot drive feedback.
  - In `CompanionRuntimeTest`, using `TestScope`:
    - `staticPolicyAppliesStillPoseWithZeroJobs`;
    - `policyFlipMidGestureLeavesZeroJobs`;
    - `hiddenStopsIdleLoop`;
    - `coachRestsSeated`;
    - `typingHoldsFirstAttentiveKeyLookingDown`;
    - `idleBeatWaitsForGesture`.
  - In `PipCompanionTest` (instrumented):
    - `pipIsHiddenFromAccessibility`: the node has no content description,
      no click action and no children in the merged tree;
    - `staticPlaybackRunsNoFrames`;
    - `tapPlaysOnlyWhenAnimated`.
- [ ] **Step 2: Run** the three JVM classes and `PipCompanionTest`.
  Expected: FAIL.
- [ ] **Step 3: Implement.** Today uses one `CompanionPresentation` and
  runtime remembered in `TodayScreen`, with surface Today. Its context has
  everything false, so Today shows resting, a greeting, idle beats (including
  the curl-up) and tap/pat. Today's moments (saved, first meal today, day
  complete, welcome back, reviewed) are carried to milestone 7.
- [ ] **Step 4: Run** the same classes plus `TodayScreenTest`. Expected: PASS.
  Toggle Developer options › "Remove animations" on the emulator and check
  that Today's Pip holds still.
- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/java/com/yakov103/mivu/pip android/app/src/main/java/com/yakov103/mivu/ui/today/TodayScreen.kt android/app/src/test/java/com/yakov103/mivu/pip android/app/src/androidTest/java/com/yakov103/mivu/pip
git commit -m "feat(android): bring Pip to life on Today with motion policy"
```

### Task 4: Coach timeline data, activity and worker fixes

**Files:**
- Create: `android/app/src/main/java/com/yakov103/mivu/diary/CoachTimeline.kt`
- Create: `android/app/src/main/java/com/yakov103/mivu/ui/coach/CoachHistoryWindow.kt`, `ui/coach/CoachReceiptPresentation.kt`
- Modify:
  - `coach/CoachEngine.kt` (`onActivity`);
  - `coach/CoachWorker.kt` (`capturedOnly` and activity);
  - `diary/DiaryDatabase.kt` (`nextPendingCoachTurn` filters);
  - `coach/CoachReplyLines.kt` (`followUps`);
  - `android/app/src/debug/java/com/yakov103/mivu/ProofSession.kt` (scratch
    profile).
- Test: `android/app/src/androidTest/java/com/yakov103/mivu/diary/CoachTimelineTest.kt`; `coach/CoachWorkerTest.kt`, `coach/CoachEngineTest.kt` (add cases); JVM `ui/coach/CoachHistoryWindowTest.kt`, `ui/coach/CoachReceiptPresentationTest.kt`

**Interfaces:**
- Consumes: from 4a, `coachCommittedReceipt(receipt)`, `Tx.coachUndo(key)`,
  `Tx.undoState(meal)`, `undoCoachChange(key)`, and the `boundedRecords`
  helper in `CoachContext.kt`.
- Produces:
  - `sealed interface CoachPageRequest { Latest; Before(ordinal: Long); After(ordinal: Long); Range(from: Long, to: Long) }`.
  - `data class CoachExchange(turn: CoachTurn /*without photo bytes*/, ordinal: Long, receipts: List<CoachCommittedReceipt>, targets: Map<String, CoachReceiptTarget>, undo: Map<String, CoachUndoState>, questionMeals: List<DiaryMeal>)`.
  - `data class CoachPage(exchanges: List<CoachExchange> /*oldest first*/, hasEarlier: Boolean, hasLater: Boolean)`.
  - `fun DiaryDatabase.coachPage(request: CoachPageRequest, limit: Int = 20): CoachPage`.
    It is one read transaction, ordered by `coach_turn.ordinal`, with
    `LIMIT limit + 1` to detect an edge. It makes bounded id reads for receipt
    targets: the meal (`mealWithoutPhotoBytes`) or the workout, plus the
    `coach_undo` state. `questionMeals` is read only for the exchange with a
    question (at most 4).
  - `sealed interface CoachReceiptTarget { Loading; Unavailable; Failed; Meal(meal, localDate); Workout(session, localDate) }`
    and `enum CoachUndoState { Available, Undone }`. Undo is `Available` only
    while `undoState(meal) == afterState` and the snapshot is not undone;
    otherwise the key is absent.
  - `fun DiaryDatabase.coachPhotoBytes(turnID: UUID, photoID: UUID): ByteArray?`.
  - `fun DiaryDatabase.retryCoachTurn(turnID: UUID)`, which sets `captured`,
    as iOS `retry`.
  - `fun DiaryDatabase.chooseCoachDay(turnID: UUID, usePrevious: Boolean)`,
    ported from iOS `chooseCoachDay`. It sets `resolvedDayID` to the previous
    day or the capture-date day, then sets `captured`.
  - `class CoachHistoryWindow`, a pure port of iOS `CoachPagedHistoryWindow`
    without measured anchors:
    - `pageSize 20`, `maximumPages 5`, `maximumExchanges 100`;
    - `reset(page)`;
    - `reserve(direction, visibleIDs: Set<UUID>): Reservation?`, which evicts
      the far edge only when no visible row is on it;
    - `complete(reservation, page)`;
    - `fail(reservation, message)`;
    - `retireAll()`, where a retired read keeps its page slot until `exited(id)`;
    - `reserveReplacement()`;
    - `edgeState(direction): Available | Loading | Exhausted | Failed(message)`;
    - `isLatest(id)`;
    - `exchanges`;
    - `occupiedPageSlots`.
  - `data class CoachReceiptPresentation(receipt, target)`, a pure port of the
    iOS struct. It has:
    - `committedStatus` ("Saved food", "Estimate awaiting review" or
      "Recorded operation");
    - `committedNutrition` (kcal or "Energy unknown");
    - `committedMacros` ("Carbs n g · Protein n g · Fat n g", with "unknown"
      for a missing value);
    - `nutritionCompleteness` ("Some nutrients unknown");
    - `estimateLabel` ("Estimated nutrition" or "Nutrition provenance unknown");
    - `targetNotice`;
    - `changeNotice` ("Edited later", "Moved to <short date>",
      "Edited · moved to <short date>" or "Status changed later");
    - `itemRows`;
    - `weightLabel` ("Weight saved · <value> <unit>").
  - `CoachEngine(..., onActivity: suspend (CoachActivity) -> Unit = {})`, with
    `enum CoachActivity { preparingPhotos, thinking, reading, saving }`
    reported at the iOS points (`CoachEngine.swift` :21, :48, :132, :173).
  - `CoachWorker`:
    - `val activity: StateFlow<Pair<UUID, CoachActivity>?>`;
    - `drain(profileID, includeWaitingForConnection: Boolean)`;
    - after a pass whose turn stayed pending, the next pass uses
      `capturedOnly = true` (`'captured','analyzing'`), so a stuck oldest turn
      cannot hold back newer messages;
    - `DiaryDatabase.nextPendingCoachTurn(includeWaitingForConnection: Boolean, capturedOnly: Boolean)`
      with the iOS state sets.
  - `CoachReplyLines.followUps(turn): List<FollowUp>` (`today`, `progress`),
    ported verbatim.
  - The debug "Run Coach turn" uses a scratch profile, opened as
    `CaptureProbeActivity` opens `PROFILE`. It runs `CoachEngine.run`
    directly, never the app worker or the selected diary.

- [ ] **Step 1: Failing tests.**
  - In `CoachTimelineTest`:
    - `latestPageHoldsTwentyNewestOldestFirst`;
    - `beforeAndAfterCursorsPage`;
    - `tenThousandTurnsStayBounded`: a seeded 10,000-turn diary, where the
      latest page and five earlier pages read with `snapshotReads == 0`;
    - `receiptTargetShowsMovedMeal`;
    - `undoAvailableUntilManualEdit`;
    - `undoneAfterUndo`;
    - `chooseDayResolvesPreviousDay`;
    - `coachPhotoBytesReadOnDemand`.
  - In `CoachHistoryWindowTest`:
    - `neverExceedsHundredExchangesWithReservations`;
    - `retiredReadKeepsSlotUntilExit`;
    - `evictsOnlyInvisibleFarEdge`;
    - `exhaustedEdgeDoesNotReserve`;
    - `failedEdgeRetries`;
    - `isLatestOnlyForTrueNewest`.
  - In `CoachReceiptPresentationTest`:
    - `savedFoodHeaderAndMacros`;
    - `unknownNutrientLabelled`;
    - `editedAndMovedNotice`;
    - `weightLabel`.
  - In `CoachWorkerTest`:
    - `stuckOldestTurnDoesNotHoldBackNewerCapture`;
    - `activityReportsPhases`.
  - In `CoachEngineTest`: `photoTurnReportsPreparingThenThinking`.
- [ ] **Step 2: Run** each class. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** each class again, plus `CoachContextTest` (it shares
  `boundedRecords`). Expected: PASS.
- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/java/com/yakov103/mivu/diary android/app/src/main/java/com/yakov103/mivu/coach android/app/src/main/java/com/yakov103/mivu/ui/coach android/app/src/debug android/app/src/test/java/com/yakov103/mivu/ui/coach android/app/src/androidTest/java/com/yakov103/mivu/diary/CoachTimelineTest.kt android/app/src/androidTest/java/com/yakov103/mivu/coach
git commit -m "feat(android): page the Coach timeline and report Coach activity"
```

### Task 5: Coach timeline screen

**Files:**
- Create:
  - `android/app/src/main/java/com/yakov103/mivu/ui/coach/CoachViewModel.kt`
  - `ui/coach/CoachScreen.kt`
  - `ui/coach/CoachTimeline.kt`
  - `ui/coach/CoachReceiptCard.kt`
  - `ui/coach/CoachQuestionChips.kt`
  - `ui/coach/CoachReplyText.kt`
- Modify: `android/app/src/main/java/com/yakov103/mivu/ui/MivuApp.kt`. It
  replaces `composable<Route.Coach> { LaterUpdate() }` and creates the
  activity-scoped `CoachViewModel` (`viewModel(viewModelStoreOwner = activity, key = "coach-$profileID")`).
- Modify: `android/app/src/main/res/drawable/` (adds `ic_arrow_downward.xml`
  from Material Symbols).
- Test: `android/app/src/androidTest/java/com/yakov103/mivu/ui/coach/CoachScreenTest.kt`; JVM `ui/coach/CoachReplyTextTest.kt`

**Interfaces:**
- Consumes: `coachPage`, `CoachHistoryWindow`, `CoachReceiptPresentation`,
  `CoachWorker.activity`, `retryCoachTurn`, `chooseCoachDay`,
  `undoCoachChange` and `followUps` from Task 4.
- Produces:
  - `class CoachViewModel(repository, profileID, drain: () -> Unit, isConnected: () -> Boolean, activity: StateFlow<Pair<UUID, CoachActivity>?>, saved: SavedStateHandle)`,
    with:
    - `val timeline: StateFlow<CoachTimelineState>`, where
      `CoachTimelineState(exchanges, earlier: EdgeState, later: EdgeState, latestID: UUID?, loaded: Boolean, error: String?)`;
    - `loadEarlier(visible: Set<UUID>)`;
    - `loadLater(visible)`;
    - `jumpToLatest()`;
    - `undo(operationKey)`;
    - `retry(turnID)`;
    - `chooseDay(turnID, usePrevious)`;
    - `answer(target, label, excerpt)`, which sets any draft aside and puts
      it back afterwards, as iOS `sendTap` does;
    - `finishRest(turnID)` ("Finish the rest" for a photo-only turn).

    On `repository.changes` it re-reads each resident page by `Range`. While
    the last page has no later page, it also reads `After(lastOrdinal)`: new
    turns join the latest page, and the earliest page is evicted only while
    the reader is at the latest. While the reader is browsing, the last page
    only gets `hasLater = true`.
  - `@Composable fun CoachScreen(model: CoachViewModel, onOpenMeal: (UUID) -> Unit, onSeeToday: () -> Unit, onSeeProgress: () -> Unit)`.
  - `fun coachReplyText(markdown: String): AnnotatedString` handles only
    `**bold**`, `*italic*` and `_italic_`. A link `[text](url)` becomes plain
    text, as iOS `attributed` does.
- **Layout** (mockup "Coach timeline"):
  - The timeline is a `LazyColumn(reverseLayout = true)` keyed by turn id.
  - A user bubble is right-aligned, accent-filled and shows its text. It shows
    "n photos" thumbnails through `coachPhotoBytes` and `decode()` from
    `MealRow.kt`, with at most 2 decodes at once (`Semaphore(2)`) and an
    `LruCache` sized at 16 MiB of bitmap bytes. While the turn is not
    completed it shows "Saved on this phone".
  - Pip's reply is `coachReplyText`.
  - Status lines use the iOS strings for each `CoachTurnState`.
  - Activity uses `CoachActivityView` titles ("Looking at your photos…",
    "Thinking…", "Checking your diary…", "Saving…"), with an M3 Expressive
    `LoadingIndicator`. Its content description is the title plus ", Your
    message is saved."
  - "Try again" and "Log to <short date>" chips follow the iOS conditions.
  - Receipt cards are shown for meal and workout receipts. A weight receipt
    is a chip with "Weight saved · …".
  - "See today" / "See progress" follow-ups and "Couldn't finish the rest"
    with **Retry** appear on the latest exchange only. Question chips also
    appear on the latest exchange only: candidates with a 44 dp thumbnail,
    title and time ("Time unspecified" when date-only). A `confirm` question
    shows **Remove**, which is destructive and sends "Remove it", and **Keep**,
    which sends "Keep it".
  - Receipt card (mockup):
    - a "Saved food" header with a check, title and kcal, a macro line in
      the protein, carbs and fat colours, the notices, and the per-dish rows
      behind a disclosure ("Nutrition details");
    - **Undo** while `Available`, "Undone" once used;
    - **Review / Edit** opens `Route.MealDetail`;
    - at `isLargeText()`, Undo moves to its own row after Review / Edit.
  - Empty state (no turns): "What would you like to record?" and "Describe a
    meal, add a photo, or record a weigh-in or workout. You can review and
    correct every estimate. Coach gives estimates, not medical advice."
  - Paging: when the last visible index is within 3 of the earlier end, call
    `loadEarlier`; when the first visible index is ≤ 3 and the later edge is
    available, call `loadLater`. Loading shows a transient spinner overlay.
    A failure shows a "Retry earlier messages" / "Retry later messages"
    overlay.
  - The list follows new items only while `firstVisibleItemIndex == 0` and
    the offset is under 2 dp (`scrollToItem(0)` after the insert).
- **Jump to latest:**
  - a 48 dp `FilledTonalIconButton` circle with `ic_arrow_downward` and
    `contentDescription = "Jump to latest"`, at the bottom end above the
    composer area;
  - shown when the reader is not at the latest, or when `later` is not
    exhausted;
  - tap: `jumpToLatest()` when later pages are missing, then
    `animateScrollToItem(0)`, or `scrollToItem` when animations are off;
  - it carries `Modifier.scrollable(listState, Orientation.Vertical, reverseDirection = true)`,
    so a drag on it scrolls the list;
  - it never calls `requestFocus`, and its `traversalIndex` places it after
    the list;
  - hidden at the latest.

- [ ] **Step 1: Failing tests.**
  - In `CoachScreenTest`, which seeds turns, receipts and questions directly
    with the 4a store calls and a no-op `drain`:
    - `emptyStateShowsIosCopy`;
    - `receiptCardShowsSavedFoodAndMacros`;
    - `undoRestoresAndCardReadsUndone`;
    - `undoHiddenAfterManualEdit`;
    - `reviewEditOpensMealDetail`;
    - `questionChipsOnlyOnLatestAndSendAnswer`;
    - `confirmShowsRemoveAndKeep`;
    - `activityShowsThinking`;
    - `needsRetryShowsTryAgain`;
    - `dayChoiceLogsToChosenDay`;
    - `earlierPagesLoadOnScroll` (60 turns);
    - `jumpToLatestAppearsAndReturns`;
    - `jumpToLatestIs48dpWithSpokenLabel`;
    - `dragOnJumpToLatestScrollsTimeline`;
    - `replyWhileBrowsingKeepsPositionWithin2dp`;
    - `largeFontStacksUndo`, at font scale 2.0.
  - In `CoachReplyTextTest`: `boldItalicAndDroppedLinks`.
- [ ] **Step 2: Run** `CoachScreenTest` and `CoachReplyTextTest`. Expected: FAIL.
- [ ] **Step 3: Implement**, and wire the destination in `MivuApp.kt`:
  - Review / Edit opens `Route.MealDetail`;
  - See today selects the Today tab;
  - See progress selects Progress.
- [ ] **Step 4: Run** both classes plus `AppShellTest`. Expected: PASS.
- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/java/com/yakov103/mivu/ui/coach android/app/src/main/java/com/yakov103/mivu/ui/MivuApp.kt android/app/src/main/res/drawable android/app/src/androidTest/java/com/yakov103/mivu/ui/coach android/app/src/test/java/com/yakov103/mivu/ui/coach
git commit -m "feat(android): show the Coach timeline with receipts, chips and Jump to latest"
```

### Task 6: Composer, drafts, Ask Pip, and Pip in Coach

**Files:**
- Create: `android/app/src/main/java/com/yakov103/mivu/ui/coach/CoachComposer.kt`, `ui/coach/CoachReplyQuote.kt`
- Modify:
  - `ui/coach/CoachViewModel.kt` (draft, send and companion);
  - `ui/coach/CoachScreen.kt` (composer, Pip strip and suggestion chips);
  - `ui/MivuApp.kt`;
  - `ui/diary/DiaryScreen.kt`;
  - `ui/meal/MealDetailScreen.kt`;
  - `ui/meal/FoodItemEditor.kt`.
  The last three replace `onAskPip: () -> Unit` with the reply they quote.
- Test: `android/app/src/androidTest/java/com/yakov103/mivu/ui/coach/CoachComposerTest.kt`; update `DiaryScreenTest`/`MealDetailScreenTest` callers.

**Interfaces:**
- Consumes:
  - `captureCoachSubmission` and `reconcileCoachCapture` from 4a;
  - `preparePhoto(resolver, uri, folder)` from `MealComposerViewModel.kt`;
  - `CompanionPresentation`, `CompanionRuntime` and `PipCompanion` from
    Task 3;
  - `CoachViewModel` from Task 5.
- Produces:
  - `data class CoachDraft(text: String, photos: List<String> /*prepared file paths*/, reply: CoachReply?, submissionID: UUID)`,
    kept in `SavedStateHandle`.
  - On `CoachViewModel`:
    - `val draft: StateFlow<CoachDraft>`;
    - `updateText(String)`, capped at 20,000;
    - `importPhotos(uris)`, at most 8, otherwise the existing
      `MealComposerViewModel` limit message;
    - `removePhoto(path)`;
    - `prefill(text): Boolean`;
    - `startReply(reply: CoachReply, draft: String? = null): Boolean`, which
      never replaces a draft that has text, photos or a quote;
    - `cancelReply()`;
    - `send(): Boolean`;
    - `val companion: StateFlow<CompanionOutput>`;
    - `reportComposer(focused: Boolean, listening: Boolean, caret: Int)`;
    - `touchPip(kind)`.
  - `fun coachMessage(error: Throwable): String`, ported from iOS
    `CoachViewModel.message(for:)` with each string verbatim ("iPhone"
    becomes "phone").
  - `sealed interface AskPip { Day(dayID, localDate); Meal(mealID, title); Food(mealID, itemID, name, dayLocalDate) }`,
    which `MivuApp` maps to iOS's reply and draft:
    - Day: excerpt `EEEE, d MMM`, no draft;
    - Meal: excerpt is the title, or "Meal";
    - Food: excerpt is the food name, and the draft is
      `"About the <name> from <EEE d MMM>: "`.

    Excerpts are at most 280 characters. Today's "Log with Pip" opens Coach
    and focuses the field with no quote.
- **Send:**
  - Build the payload from the current head (time zone, active day, previous
    day confirmation, segment) and the draft's `submissionID`, then call
    `captureCoachSubmission(payload, head.revision)`.
  - On `DiaryError.StaleRevision`, rebuild the context once and retry.
  - On any other failure, call `reconcileCoachCapture`. `Accepted` counts as
    sent. Otherwise the draft is kept and `coachMessage(e)` is shown.
  - On success: clear the draft, take a new `submissionID`, call `drain()`,
    and send the presentation a `CompanionSubmission`, then a `Saved` event.
  - A photo import sends a `PhotoAdded` event (curious).
- **Companion context:**
  - `isTyping` = (field focused or listening) and not sending;
  - `isProcessing` = worker activity for this profile;
  - `needsRecovery` = a send error, or the latest exchange in `needsRetry`,
    `waitingForConnection` or `waitingForNetwork`.
- **Layout** (mockup "Composer with drafts", edge to edge):
  - The composer is docked above the navigation bar with `imePadding()`.
    The navigation bar hides while the IME is visible.
  - Draft thumbnails (64 dp) each have a 48 dp ✕ ("Remove photo n") and a
    count ("n of 8 photos").
  - Pip peeks over the field's left top edge, with the caption "Logging to
    <dayLabel> · <n> kcal goal" (`CoachReplyLines.dayLabel`). In recovery the
    caption shows `coachMessage`, or "Your message is safe here".
  - The quote sits at the top of the field: "From Diary" or "Replying to
    Pip" / "Replying to you", the excerpt, and a 48 dp **Cancel reply**.
  - The field placeholder is "Describe a meal…". The camera icon
    ("Add photos") is inside the field and opens the picker in this task; it
    opens the camera in Task 7.
  - One round action: the mic while the draft is empty (inert until Task 8),
    **Send** once there is something to send.
  - Suggestion chips appear only in the empty state, in a horizontally
    scrolling row. They fill the draft only: "Log breakfast" → "For breakfast
    I had ", "Log my weight" → "My weight this morning is ", "How am I doing
    today?" → the same text.
  - Footnote: when not connected
    (`credentials.registrations().isEmpty()`), "Messages save on this phone."
    When connected, "Using ChatGPT plan · Manage usage", linking to
    `https://chatgpt.com/settings/usage`. The "Connect ChatGPT for replies"
    link waits for a release sign-in screen and is carried to 4c.

- [ ] **Step 1: Failing tests.** In `CoachComposerTest`:
  - `sendSavesTurnAndClearsDraft`;
  - `uncertainSaveReconcilesWithoutDuplicate`, where the capture throws after
    the commit through a test hook and only one turn exists;
  - `micWhenEmptySendWhenText`;
  - `photoPickerAddsUpToEightAndRemoves`, using an espresso-intents stub for
    the picker result;
  - `suggestionChipFillsDraftOnly`;
  - `askPipFromFoodQuotesAndPrefills`;
  - `askPipKeepsDraftInProgress`;
  - `cancelReplyRemovesQuote`;
  - `draftSurvivesRecreate`;
  - `pipPeeksAboveFieldHiddenFromAccessibility`;
  - `sendShowsSubmittedThenSaved`, which reads `companion`;
  - `largeFontKeepsSendReachable`, at font scale 2.0.
- [ ] **Step 2: Run** `CoachComposerTest`. Expected: FAIL.
- [ ] **Step 3: Implement**, and wire Ask Pip from `DiaryScreen`,
  `MealDetailScreen` and `FoodItemEditor` through `MivuApp`
  (`coach.startReply(...)`, then select the Coach tab). Remove their
  `shortcut:` comments.
- [ ] **Step 4: Run** `CoachComposerTest`, `CoachScreenTest`,
  `DiaryScreenTest` and `MealDetailScreenTest`. Expected: PASS.
- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/java/com/yakov103/mivu/ui android/app/src/androidTest/java/com/yakov103/mivu/ui
git commit -m "feat(android): compose Coach messages with photos, Ask Pip quotes and Pip"
```

### Task 7: In-app camera

**Files:**
- Modify: `android/gradle/libs.versions.toml` (`camerax`: `camera-camera2`,
  `camera-lifecycle`, `camera-compose`), `android/app/build.gradle.kts`.
- Modify: `android/app/src/main/AndroidManifest.xml`. Add
  `android.permission.CAMERA` and
  `<uses-feature android:name="android.hardware.camera.any" android:required="false"/>`.
- Create: `android/app/src/main/java/com/yakov103/mivu/ui/coach/CoachCameraScreen.kt`
- Modify:
  - `ui/MivuApp.kt` (a `Route.CoachCamera` full-screen dialog destination,
    so Coach is covered and Pip goes hidden);
  - `ui/coach/CoachViewModel.kt` (`addCapturedPhoto(file: File)`, which runs
    the same `preparePhoto` path);
  - `ui/coach/CoachComposer.kt` (the camera icon opens the camera).
- Test: `android/app/src/androidTest/java/com/yakov103/mivu/ui/coach/CoachCameraTest.kt`

**Interfaces:**
- Consumes: the `CoachViewModel` draft from Task 6.
- Produces: `@Composable fun CoachCameraScreen(model: CoachViewModel, permission: CameraPermission = rememberCameraPermission(), onClose: () -> Unit)`,
  with `enum CameraPermission { Granted, Denied, PermanentlyDenied, Unknown }`
  (the parameter lets tests drive denial). The camera never sends.
  - **Preview:** `CameraXViewfinder` with a `Preview` and `ImageCapture`
    bound to the destination's lifecycle. It shows a close button (✕), the
    "n of 8 photos" chip, a 72 dp shutter ("Take photo"), and **Choose
    photos**, which opens the Photo Picker for the remaining slots.
  - **Shutter:** `takePicture` into the draft folder, then `addCapturedPhoto`.
    The camera stays open until 8 photos are taken or ✕ is tapped.
  - **Denied:** "Allow camera access in Settings, or choose photos.", with
    **Open Settings** (`ACTION_APPLICATION_DETAILS_SETTINGS`) and **Choose
    photos**.
  - **Errors:** "Camera is unavailable. Choose photos instead.", "Camera was
    interrupted. Your input is kept.", "Could not take photo. Your note and
    other photos are kept." and "Preparing camera…", all verbatim from iOS.
  - **Lifecycle:** an activity recreation keeps the draft, because it lives
    in the view model.

- [ ] **Step 1: Failing tests:**
  - `captureAddsPhotoAndStaysOpen`, on the emulator's virtual back camera;
  - `closeReturnsToComposerWithDraft`;
  - `deniedKeepsDraftAndOffersChoosePhotos`;
  - `fullDraftDisablesShutter`;
  - `recreateMidCaptureKeepsDraft`.
- [ ] **Step 2: Run** `CoachCameraTest`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `CoachCameraTest` and `CoachComposerTest`. Expected: PASS.
- [ ] **Step 5: Commit**

```bash
git add android/gradle/libs.versions.toml android/app/build.gradle.kts android/app/src/main/AndroidManifest.xml android/app/src/main/java/com/yakov103/mivu/ui android/app/src/androidTest/java/com/yakov103/mivu/ui/coach/CoachCameraTest.kt
git commit -m "feat(android): take Coach photos with the in-app camera"
```

### Task 8: Voice input

**Files:**
- Create: `android/app/src/main/java/com/yakov103/mivu/ui/coach/CoachVoiceInput.kt`
- Modify: `android/app/src/main/AndroidManifest.xml`. Add `RECORD_AUDIO` and
  `<queries><intent><action android:name="android.speech.RecognitionService"/></intent></queries>`.
- Modify: `ui/coach/CoachComposer.kt` (mic and Stop, the level wave, the voice note).
- Test: JVM `android/app/src/test/java/com/yakov103/mivu/ui/coach/CoachVoiceInputTest.kt`; instrumented `ui/coach/CoachVoiceTest.kt`

**Interfaces:**
- Consumes: `CoachViewModel.updateText` and `reportComposer(listening = true)`.
- Produces:
  - `class CoachVoiceInput(context: Context, available: Boolean = SpeechRecognizer.isRecognitionAvailable(context))`:
    - `val phase: StateFlow<Phase /*Idle, Preparing, Listening*/>`;
    - `val levels: StateFlow<List<Float>>`;
    - `val note: StateFlow<String?>`;
    - `fun start(draft: String, update: (String) -> Unit)`;
    - `fun stop()`;
    - `val listener: RecognitionListener`, which tests drive directly.

    It prefers `createOnDeviceSpeechRecognizer` when
    `isOnDeviceRecognitionAvailable`, with `EXTRA_PARTIAL_RESULTS`, language
    `en-US`, and `LANGUAGE_MODEL_FREE_FORM`.
  - `companion fun merged(draft: String, spoken: String): String`, ported
    verbatim.
  - `companion fun level(rmsDb: Float): Float`, which maps `onRmsChanged`
    from -2..10 dB onto 0..1.
- **Copy** (verbatim, "iPhone" → "phone"):
  - "Allow microphone access in Settings to log by voice.";
  - "Voice input isn't available on this phone. Type, or use the keyboard
    microphone.";
  - "Voice input stopped. Your text is kept.";
  - button labels "Speak your meal" / "Stop listening".

  "Listening" is announced through `announceForAccessibility`. Stop is the
  red round button from the mockup. Leaving the screen
  (`ON_PAUSE`) stops and destroys the recognizer, and the text is kept.

- [ ] **Step 1: Failing tests.**
  - In `CoachVoiceInputTest`:
    - `mergedAddsOneSpace`;
    - `mergedKeepsDraftOnEmptySpeech`;
    - `levelClamps`.
  - In `CoachVoiceTest`:
    - `partialResultsStreamIntoDraft`;
    - `errorKeepsTextAndShowsNote`;
    - `unavailableShowsMessage`;
    - `stopButtonHasSpokenLabel`;
    - `pausingStopsListening`.
- [ ] **Step 2: Run** both classes. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** both classes and `CoachComposerTest`. Expected: PASS.
- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/AndroidManifest.xml android/app/src/main/java/com/yakov103/mivu/ui/coach android/app/src/test/java/com/yakov103/mivu/ui/coach android/app/src/androidTest/java/com/yakov103/mivu/ui/coach
git commit -m "feat(android): log to Coach by voice"
```

### Task 9: Milestone 4 evidence and parity

**Files:**
- Create:
  - `docs/verification/2026-10-24-android-coach-screens.md`;
  - `docs/verification/android-coach/*.png`;
  - `android/app/src/androidTest/java/com/yakov103/mivu/ui/coach/CoachFixtureSeed.kt`,
    run by hand only and excluded like `TodayFixtureSeed`.
- Modify:
  - `docs/parity.md`;
  - `docs/superpowers/plans/android-carried-items.md`;
  - `.agents/skills/mivu-animation/SKILL.md` (one Android row per owner:
    rig asset, scene, motion, runtime, policy and preview);
  - `android/app/build.gradle.kts` (add the seed to `notClass`).

- [ ] **Step 1: Run the full suite once** at a clean commit:
  `./gradlew :app:testDebugUnitTest :app:connectedDebugAndroidTest :app:lintDebug :app:assembleRelease --rerun-tasks`,
  then `python3 scripts/ci/parity.py` and the `scripts/ci` unit tests. Record
  the SHA, the emulator, and the counts from the JUnit XML. Never count a
  skipped or zero-test class. If a class fails, fix it, or record it
  honestly with its cause.
- [ ] **Step 2: Screenshots.** Seed synthetic turns with `CoachFixtureSeed`.
  Capture in light, dark and font scale 2.0:
  - `coach-empty`;
  - `coach-timeline`, with a receipt, chips and Thinking;
  - `coach-browsing`, with Jump to latest;
  - `coach-composer-reply`, a quote with photos;
  - `coach-camera`;
  - `coach-voice`;
  - `today-pip`.

  Also record a short screen recording of Pip on Coach and Today, kept
  outside Git, and link its local path in the record. Compare against the
  approved mockup.
- [ ] **Step 3: Parity.**
  - `coach-capture` becomes `done` if text, photo, camera and voice capture
    are all tested.
  - `coach-history` becomes `partial` (the history screen is 4c).
  - `coach-reply` becomes `partial` (seek and long-press are 4c).
  - `coach-voice`, `coach-floating-composer` and `pip-entry-points` become
    `partial` or `done` as tested.
  - `pip` becomes `partial` (Coach and Today resting are done; Today moments
    are milestone 7; Progress is pending).
  - `coach-context` and `coach-edit-parity` lose their "UI pending" note.
  - The `today` and `diary` notes now say that Pip is animated and that Ask
    Pip is wired.
- [ ] **Step 4: Carried items.**
  - Remove the delivered Milestone 4 items: `capturedOnly`, scratch profile,
    camera, and Ask Pip.
  - Move the remaining Milestone 4 items under a "Milestone 4c" heading,
    adding: "Connect ChatGPT for replies" link, photo Retake, markdown beyond
    emphasis if needed.
  - Add "Milestone 7: Today Pip moments (saved, first meal today, day
    complete, welcome back, reviewed)".
- [ ] **Step 5: Commit**

```bash
git add docs/verification/2026-10-24-android-coach-screens.md docs/verification/android-coach docs/parity.md docs/superpowers/plans/android-carried-items.md .agents/skills/mivu-animation/SKILL.md android/app/build.gradle.kts android/app/src/androidTest/java/com/yakov103/mivu/ui/coach/CoachFixtureSeed.kt
git commit -m "docs(verification): record the Android Coach screens and Pip"
```
