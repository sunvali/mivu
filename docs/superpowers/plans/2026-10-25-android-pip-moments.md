# Android Pip Moments on Today Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring Today's Pip to iOS parity for milestone 7:
- the Today moments: saved, first meal today, reviewed and welcome back;
- the re-greet after the app returns from the background;
- Pip goes still when it is half scrolled off;
- the open Pip leftovers from milestone 4b.

**Architecture:** The moment-to-gesture table is already ported
(`PipGestureLibrary.gesture`, M4b Task 2), and so are the `PipMoment`s and the
`MivuMotion` timings. This milestone does three things:
- widens `CompanionPresentation` to iOS: the poses, event kinds, welcome back
  and `enterBackground`;
- moves Today's presentation from `remember` in `TodayScreen` into
  `TodayViewModel`, as `CoachViewModel` already holds Coach's. The view model
  outlives navigation, so a capture screen's durable save is no longer lost
  and closing the composer no longer re-greets;
- feeds it the iOS signals after durable writes only.

**Tech Stack:** Kotlin, Jetpack Compose (`Modifier.onVisibilityChanged`,
`LifecycleEventEffect` from lifecycle-runtime-compose, `LocalActivity`),
`SharedPreferences`, JUnit and Compose UI instrumented tests. No new
dependency.

**Spec:** [`docs/superpowers/specs/2026-10-19-pip-layered-rig-design.md`](../specs/2026-10-19-pip-layered-rig-design.md)
and the Android spec [`2026-10-23-android-app-design.md`](../specs/2026-10-23-android-app-design.md)
(feature map row `pip`). The contract is the
[mivu-animation skill](../../../.agents/skills/mivu-animation/SKILL.md).

The scope comes from:
- [`android-carried-items.md`](android-carried-items.md), "Milestone 7";
- [`docs/parity.md`](../../parity.md): the `pip` row, and the `today` note;
- the M4b ledger
  `.superpowers/sdd/2026-10-24-android-coach-screens/progress.md`
  (Tasks 2 and 3). None of these leftovers was closed in M6
  (`.superpowers/sdd/2026-10-24-android-progress-onboarding/progress.md`).

**iOS sources** (the source of truth):
- `ios/Mivu/Design/CompanionPresentation.swift`: poses, `Kind.pose` and
  `duration`, `attach(lastActiveAt:)`, `welcomeBackDue`, `enterBackground`,
  `CompanionLastActive`;
- `ios/Mivu/Design/CompanionRuntime.swift` 195–215 and
  `PipGestureLibrary.swift` 315–330: the moment table;
- `ios/Mivu/Design/MotionPolicy.swift`;
- `ios/Mivu/Diary/TodayView.swift` 190–260 (phase, events), 465–520
  (`attachCompanion`, `receiveCompanionEvent`) and 725–760 (`covered`,
  `onScrollVisibilityChange(threshold: 0.5)`);
- `ios/Mivu/Diary/DiaryViewModel.swift` 278–286 (`acceptReview`), 365–370
  (saved after the durable write) and 403–409 (`noteFirstMealOfDay`);
- `ios/Mivu/Design/PipRigView.swift` 428–434 (the heart pop).

## Scope decisions

**Kept:**
- **Saved** on Today after a capture screen (composer, manual entry) hands back
  its saved meal, and after the morning weigh-in (already there).
- **First meal today**, decided after the write from refreshed state, as iOS
  `noteFirstMealOfDay`: the meal is on the active day, it is the day's only
  meal, and it has exactly one submission.
- **Reviewed** after "Accept" on meal detail succeeds.
- **Welcome back** instead of the greeting when the person last left the app
  on an earlier calendar day (iOS `Calendar.startOfDay`, not the waking day).
- **Re-greet** after the app returns from the background, on Today and Coach,
  since iOS resets its one shared presentation.
- **Half-scroll hide:** Pip is `Hidden` while less than half of it is
  visible.
- The **MotionPolicy read-before-register gap** and the **main-thread KDoc** on
  `PipMotion` and `PipPlayer`.

**Decided, each with its reason:**
- **The background signal is the activity's lifecycle, not the nav entry's.**
  Today's `NavBackStackEntry` stops whenever a capture screen opens, which iOS
  treats as `covered`, not background. `TodayScreen` and `CoachScreen` observe
  `LocalActivity.current` (a `ComponentActivity`) with `LifecycleEventEffect`:
  `ON_STOP` → `enterBackground()`, `ON_START` → `enterForeground()`. A
  rotation also stops the activity; it re-greets, which is harmless.
- **Welcome back is Today's only.** Today is the start destination. Coach has
  its own presentation on Android, so giving it welcome back too would play it
  twice on one return. Coach gets the re-greet only.
- **Reviewed reaches Today only when Today is in the back stack.** Meal detail
  opened from Today calls `TodayViewModel.receiveReviewed`. From Diary there is
  no Today on screen within the 10 s feedback lifetime, so nothing is lost
  compared with iOS in practice.
- **Day complete is not wired.** iOS defines the pose, kind and gesture but no
  code emits `.dayComplete` (`DiaryViewModel` has no producer). Android keeps
  the existing `PipMoment.DayComplete` mapping and adds no producer. Adding one
  would be new behaviour, not parity.
- **`characterChanged` is `n/a`.** Android has one character and no character
  selection (`CharacterCatalog`, `CompanionSelection` are not ported). It
  arrives with selection.
- **The heart pop stays as it is.** iOS pops `transform.scale` to 1.0; Android
  pops to the pose's target scale. Every heart key in `fixtures/pip/gestures.json`
  has scale `[1, 1]`, so they agree. A test pins that, so a future gesture
  cannot make them drift silently.
- **Last-active time** is a device preference in `DiaryRepository.preferences`
  under iOS's key `companion.lastActive.<profileUUID>`, as epoch ms. Android
  has no profile deletion yet, so there is no `forget` (it joins the profiles
  Settings item).

## Global Constraints

- **Paths:** `A/` = `android/app/src/main/java/com/yakov103/mivu/`, `T/` =
  `android/app/src/test/java/com/yakov103/mivu/`, `I/` =
  `android/app/src/androidTest/java/com/yakov103/mivu/`.
- **Priority** (verbatim): policy > recovery > typing > fresh success
  (including affection and habit moments) > processing > tap/pat > greeting >
  idle beats > rest.
- **Never celebrate or comment on food amounts.** `CompanionEvent` carries no
  amounts; no confetti, points or streak counters.
- **Saved feedback follows durable local capture.** No event is emitted before
  the write returns, or for a write that failed.
- **Durations** come from `MivuMotion` (`reviewed` 0.65, `firstMealToday` 1.0,
  `welcomeBack` 1.6, `feedbackLifetime` 10). Events are deduplicated per
  (profile, operation, kind).
- **Policy:** hidden, covered, background, "Remove animations", Power Saver and
  severe thermal status show the still pose, with zero jobs.
- `CompanionPresentation` is used from the main thread only.
- Pip stays hidden from accessibility; no new copy.
- **Synthetic data only**, from `I/ui/today/TodayFixture.kt`.
- **Speed:** each task runs only its own classes; the full suite runs once, in
  Task 3; one batch review after Task 3.

  ```sh
  cd android
  ./gradlew :app:testDebugUnitTest --tests '*<Class>'
  ./gradlew :app:connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=com.yakov103.mivu.<pkg>.<Class>
  ```

## Review Focus

1. **The composer closes after the day's first meal:** Pip plays first meal
   today once; it does not greet again. (Task 2:
   `firstMealPlaysOnceAfterTheComposerReturns`)
2. **The second meal of the day:** Pip plays saved, never first meal today.
   (Task 2: `secondMealIsSavedOnly`)
3. **The app opens the morning after:** welcome back once; a later return the
   same day greets normally. (Task 1: `welcomeBackOnceAfterADayAway`; Task 2:
   `foregroundOnALaterDayWelcomesBack`)
4. **"Remove animations" or Power Saver is on when a moment arrives:** the
   still pose, and the moment is not replayed when motion returns. (Task 1:
   `staticPlaybackDropsAPendingMoment`)
5. **Back to Today more than 10 s after accepting a review:** resting, not a
   late reviewed. (Task 1: `pendingMomentExpiresAfterTheLifetime`)

---

### Task 1: Presentation parity: poses, welcome back and enterBackground

**Files:**
- Modify:
  - `A/pip/CompanionPresentation.kt`;
  - `A/pip/CompanionRuntime.kt` (`moment()` gains the new poses).
- Test: `T/pip/CompanionPresentationTest.kt`, `T/pip/PipGestureLibraryTest.kt`.

**Interfaces:**
- Produces:
  - `CompanionPose` gains `Reviewed`, `FirstMealToday`, `DayComplete` and
    `WelcomeBack` (`DayComplete` keeps the enum and the runtime map aligned
    with iOS; nothing emits it).
  - `CompanionEvent.Kind` gains `Reviewed`, `FirstMealToday` and
    `DayComplete`, each mapped to its pose and `MivuMotion` duration as iOS
    `Kind.pose` / `Kind.duration`.
  - `class CompanionPresentation(nowMs: () -> Long, zone: () -> ZoneId = ZoneId::systemDefault)`.
  - `fun attach(profileID: UUID?, lastActiveAt: Long? = null)`. When
    `lastActiveAt` is non-null, `welcomeBackDue` = its local date in `zone()`
    is before today's. A profile change clears `welcomeBackDue`.
  - `fun enterBackground()`: iOS's reset (profile null, `received` and
    `receivedSubmissions` cleared, `greetingAvailable = true`, taps and
    `welcomeBackDue` cleared).
  - The greeting slot plays `WelcomeBack` (deadline `MivuMotion.welcomeBack`)
    when due, else `Greeting`. `WelcomeBack` joins `INTERRUPTIBLE` and
    `TOUCHABLE`.
  - `class CompanionLastActive(prefs: SharedPreferences)` with
    `fun at(profileID: UUID): Long?` and `fun record(profileID: UUID, at: Long)`,
    key `"companion.lastActive." + profileID`.
  - `CompanionRuntime.moment()`: `Reviewed`, `FirstMealToday`, `DayComplete`
    and `WelcomeBack` map to the existing `PipMoment`s.

- [ ] **Step 1: Failing tests** in `CompanionPresentationTest` (`t` is
  2027-01-15 08:00 UTC; use `zone = { ZoneOffset.UTC }`):
  - `welcomeBackOnceAfterADayAway`: `attach(owner, lastActiveAt = t - 86_400_000)`
    → `WelcomeBack`; after its deadline → `Resting`;
    `enterBackground()` then `attach(owner, lastActiveAt = t)` → `Greeting`.
  - `sameDayReturnGreets`: `lastActiveAt = t - 60_000` → `Greeting`.
  - `enterBackgroundGreetsAgain`: greeting consumed, `enterBackground()`,
    `attach(owner)` → `Greeting` again.
  - `habitAndReviewKindsPlayTheirPoses`: `Reviewed` → `Reviewed` with
    `nextDeadline == now + 650`; `FirstMealToday` → `FirstMealToday`,
    `now + 1000`.
  - `firstMealReplacesAPlayingSaved`: `Saved` resolved, then `FirstMealToday`
    100 ms later → `FirstMealToday`.
  - `staticPlaybackDropsAPendingMoment`: a `Reviewed` event resolved under
    `StaticPose`, then `Animated` → `Resting`.
  - `pendingMomentExpiresAfterTheLifetime`: received under `Hidden`, resolved
    `Animated` at `+10_001` → `Resting`.
  - `processingInterruptsWelcomeBack` → `Thinking`.
  - In `PipGestureLibraryTest`: `heartsAlwaysPopToScaleOne`. Every `heart-*`
    joint in every gesture key has `scaleX == scaleY == 1f`, the scale iOS
    pops to.
- [ ] **Step 2: Run** `*CompanionPresentationTest` and `*PipGestureLibraryTest`.
  Expected: FAIL (unresolved `WelcomeBack`, `lastActiveAt`, `enterBackground`).
- [ ] **Step 3: Implement** the interfaces above. Update the class KDocs:
  remove "come in milestone 7", and add "main thread only".
- [ ] **Step 4: Run** those two classes and `*CompanionRuntimeTest`.
  Expected: PASS.
- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/java/com/yakov103/mivu/pip android/app/src/test/java/com/yakov103/mivu/pip
git commit -m "feat(android): add Pip's welcome back, reviewed and first-meal poses"
```

### Task 2: Today moments, re-greet and half-scroll hide

**Files:**
- Modify:
  - `A/ui/today/TodayViewModel.kt` (owns the presentation);
  - `A/ui/today/TodayScreen.kt` (`rememberTodayPip` keeps only the assets and
    runtime);
  - `A/ui/meal/MealDetailViewModel.kt` (`acceptReview` reports success);
  - `A/ui/MivuApp.kt` (`onReviewed` wiring);
  - `A/ui/coach/CoachViewModel.kt` and `CoachScreen.kt` (re-greet).
- Test:
  - `I/ui/today/TodayCompanionTest.kt` (new): it builds `TodayViewModel` on
    the fixture diary and asserts `companion.value`;
  - `I/ui/today/TodayScreenTest.kt`.

**Interfaces:**
- Consumes: Task 1's `attach(profileID, lastActiveAt)`, `enterBackground()`,
  `CompanionLastActive` and the new kinds.
- Produces, on `TodayViewModel`:
  - `val companion: StateFlow<CompanionOutput>`, resolved on every input with
    the Today context (nothing typing, processing or failing), and re-resolved
    at `nextDeadline` from `viewModelScope`, as `CoachViewModel.resolveCompanion`;
  - `fun reportPlayback(playback: Playback)`;
  - `fun touchPip(kind: CompanionTouch): Boolean`;
  - `fun enterBackground()`: it records `CompanionLastActive` now, then calls
    `presentation.enterBackground()`;
  - `fun enterForeground()`: it calls
    `attach(profileID, lastActive.at(profileID))`. The view model's `init`
    makes the same call;
  - `fun receiveReviewed(submissionID: UUID)`: a `Reviewed` event at the
    current time;
  - `showReceipt(mealID)` also receives `Saved` (operation = `mealID`). Then
    it waits up to 2 s for `state` to contain the meal, and receives
    `FirstMealToday` when `meals.map { it.id } == listOf(mealID)`, the meal's
    `dayID == activeDayID` and `submissions.size == 1`;
  - `saveMorningWeight` receives its `Saved` on the main thread. The
    `companionEvents` flow is removed.
- `fun MealDetailViewModel.acceptReview(submissionID: UUID, revision: Int, onAccepted: () -> Unit = {})`,
  through the existing `change(onDone)`.
- `MealDetailScreen` gains `onReviewed: (UUID) -> Unit`. `MivuApp` resolves
  Today's view model from
  `runCatching { navController.getBackStackEntry<Route.Today>() }.getOrNull()`,
  with the Today destination's key and factory.
- `CoachViewModel.enterBackground()` / `enterForeground()`: the presentation's
  `enterBackground()` / `attach(profileID)`, then `resolveCompanion()`.
- In `TodayScreen`:
  - the Pip box carries `Modifier.onVisibilityChanged(minFractionVisible = 0.5f)`,
    plus an `onDispose`, which set a hoisted `pipVisible`;
  - `reportPlayback(if (pipVisible) rememberMotionPlayback() else Hidden)`,
    and `Hidden` on dispose, as `CoachScreen`;
  - `LifecycleEventEffect(ON_STOP / ON_START, LocalActivity.current as ComponentActivity)`.
    `CoachScreen` does the same.

- [ ] **Step 1: Failing tests.**
  - `TodayCompanionTest`. Each test calls `reportPlayback(Animated)` and waits
    out the greeting first, unless noted:
    - `firstMealPlaysOnceAfterTheComposerReturns`. Capture one meal into an
      empty active day through the fixture, `reportPlayback(Hidden)`,
      `showReceipt(id)`, then `reportPlayback(Animated)` →
      `FirstMealToday`. After its deadline → `Resting`, and no `Greeting`
      appears in the trail.
    - `secondMealIsSavedOnly`: on the seeded day → `Saved`, never
      `FirstMealToday`.
    - `reviewedPlaysOncePerSubmission`: `receiveReviewed(s)` twice →
      `Reviewed` once.
    - `foregroundOnALaterDayWelcomesBack`. Record last-active as yesterday in
      the preferences, then `enterBackground()`, `enterForeground()` →
      `WelcomeBack` (no greeting wait).
    - `backgroundAndBackGreetsAgain` → `Greeting`.
  - `TodayScreenTest`: `pipStopsWhenScrolledAwayAndResumes`. Compose
    `TodayScreen` with a held view model over a diary with eight meals.
    Scroll the list to the weight row → `companion.value.playback == Hidden`;
    scroll to the top → `Animated`.
- [ ] **Step 2: Run** `TodayCompanionTest` and `TodayScreenTest`. Expected:
  FAIL (unresolved `companion`, `receiveReviewed`, `enterForeground`).
- [ ] **Step 3: Implement** the interfaces above. Update the `TodayScreen`
  KDoc to list the moments now shown.
- [ ] **Step 4: Run** those two classes, then `MorningCheckInTest`,
  `MealDetailScreenTest` and `CoachComposerTest`, since their wiring moved.
  Expected: PASS.
- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/java/com/yakov103/mivu/ui android/app/src/androidTest/java/com/yakov103/mivu/ui/today
git commit -m "feat(android): show Pip's moments on Today"
```

### Task 3: Policy gap, KDoc, full suite, evidence and parity

**Files:**
- Modify:
  - `A/pip/MotionPolicy.kt`;
  - `A/pip/PipMotion.kt` (KDoc on `PipMotion` and `PipPlayer`);
  - `docs/parity.md`;
  - `docs/superpowers/plans/android-carried-items.md`.
- Create: `docs/verification/2026-10-25-android-pip-moments.md`.

**Interfaces:** none new.

- [ ] **Step 1: Close the read-before-register gap.** In
  `rememberMotionPlayback`'s `DisposableEffect`, after the three
  registrations, re-read `removeAnimations` (from
  `Settings.Global.ANIMATOR_DURATION_SCALE`), `powerSave` and `thermal`. A
  change between `remember` and registration is then not lost. This is a
  race, so no test can pin it; `MotionPolicyTest` still passes. Add
  "Main thread only: the frame loop, springs and player jobs share unsynchronized
  state." to both KDocs.
- [ ] **Step 2: Run the full suite once** at a clean commit:
  `./gradlew :app:testDebugUnitTest :app:connectedDebugAndroidTest :app:lintDebug :app:assembleRelease --rerun-tasks`,
  then `python3 scripts/ci/parity.py` and the `scripts/ci` unit tests.
  - Record the SHA, the emulator, and the counts from the JUnit XML.
  - Never count a skipped or zero-test class.
  - Fix a failing class, or record it honestly with its cause.
- [ ] **Step 3: Record.** The verification record lists:
  - the named tests from Tasks 1–2;
  - the decisions above (day complete, `characterChanged`, heart pop, Coach
    re-greet only);
  - limits: Pip's frame rate needs an idle host or a real phone (Play
    readiness, unchanged).
- [ ] **Step 4: Parity.**
  - `pip`: Android `done` with this record if every named test passed; the
    note keeps the frame-rate limit and `characterChanged` `n/a`.
  - `today`: remove "the Today moments come in milestone 7" from the note; set
    it to `done` only if nothing else in the note remains.
- [ ] **Step 5: Carried items.**
  - Remove "Milestone 7", with its outcome.
  - Add under "Later":
    - "Pip `characterChanged` and character selection";
    - "Day complete: iOS has no trigger yet".
  - Add to the profiles Settings item: "forget `companion.lastActive` on
    profile delete".
- [ ] **Step 6: Commit**

```bash
git add android/app/src/main/java/com/yakov103/mivu/pip docs/verification/2026-10-25-android-pip-moments.md docs/parity.md docs/superpowers/plans/android-carried-items.md
git commit -m "fix(android): read Pip's motion policy after registering and record milestone 7"
```

**Final review** of the whole milestone runs here (one batch Ponytail Review).
