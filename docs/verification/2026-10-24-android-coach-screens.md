# Android Coach screens and Pip verification

Recorded 2026-10-24. Plan: Android Coach screens and Pip (plan 4b), milestone 4 close.

- Source SHA tested: `882e10179240d5c0375de5886c52ab1ccff6131b` (branch `docs/android-design`, clean tree). It adds
  only the screenshot seed to `a1609589`. The next commit, `e93b81b6`, moves those seeds under the excluded
  `TodayFixtureSeed` class (see the note below). It changes test sources and Gradle only, and was not re-run in full.
- Environment: macOS 27.0.1, Android Studio JBR, Gradle 9.8.2; emulator `Medium_Phone_API_37.0` (emulator-5554,
  API 37). The host was heavily loaded (load average 14–24). Counts are summed from the JUnit result XML.
- Command (one run, `--rerun-tasks`):

  ```sh
  cd android && ./gradlew :app:testDebugUnitTest :app:connectedDebugAndroidTest :app:lintDebug :app:assembleRelease --rerun-tasks --continue
  ```

- Result: BUILD SUCCESSFUL in 14 min 35 s.
  - `:app:testDebugUnitTest`: 233 tests, 0 failed, 0 errors, 0 skipped.
  - `:app:connectedDebugAndroidTest`: 255 tests in 31 classes, 0 failed, 0 errors. Not counted: 3 `CoachFixtureSeed`
    entries. The emulator ran them and each stopped at its `assumeTrue`, which the XML reports as a failure. They
    ran because only the first entry of a comma-separated `notClass` reached the runner under Gradle. They wiped
    nothing, because the wipe comes after the assumption. Fixed in `e93b81b6`: the Coach seeds are now methods of
    `TodayFixtureSeed` and use a `CoachFixture` helper, and the Gradle exclusion is back to the single class. With the
    debug and test APKs from `e93b81b6` installed, a log-only listing with that `notClass` returned no seed class.
  - `:app:lintDebug`: 0 errors, 14 warnings, 1 hint. `:app:assembleRelease` passed.
  - `MealEditorsTest` (known flake `failedScaleKeepsTheTypedTarget`) passed 7/7; no rerun was needed.
- After the parity update, `python3 scripts/ci/parity.py` passed, and
  `python3 -m unittest discover -s scripts/ci -p 'test_*.py' < /dev/null` ran 53 tests, all OK. The `native.sh`
  stub reads stdin, so the run needs stdin closed or it waits.
- Earlier attempt: the same command at `a1609589` stopped after 2 minutes at the device step. Gradle skipped the
  emulator because of an "Unknown API Level" error while the emulator was under load, so no instrumented test ran.
  It is not counted.

## Per-class counts

All have 0 failures and 0 errors.

| JVM class | Tests | Instrumented class | Tests |
|---|---|---|---|
| `ResponsesClientTest` | 12 | `ConnectionProofScreenTest` | 2 |
| `SampleAnalyzerTest` | 8 | `MealAnalysisWorkerTest` | 6 |
| `CoachReplyCheckTest` | 2 | `CoachContextTest` | 9 |
| `CoachToolsTest` | 12 | `CoachEngineTest` | 11 |
| `AuthSessionTest` | 19 | `CoachReadsTest` | 4 |
| `IdTokenValidatorTest` | 8 | `CoachWorkerTest` | 8 |
| `LoopbackCallbackTest` | 5 | `CredentialStoreTest` | 7 |
| `OAuthAttemptTest` | 12 | `ArchiveRoundTripTest` | 5 |
| `DayStatusTest` | 4 | `CoachProgressWritesTest` | 4 |
| `DiaryArchiveTest` | 7 | `CoachTimelineTest` | 9 |
| `DiaryMathTest` | 8 | `CoachWritesTest` | 18 |
| `DiaryModelsTest` | 4 | `DiaryCaptureTest` | 16 |
| `DiaryRestoreTest` | 5 | `DiaryDatabaseTest` | 23 |
| `DiaryValidationTest` | 21 | `DiaryDaysTest` | 1 |
| `SwiftJsonTest` | 8 | `DiaryQueriesTest` | 4 |
| `CompanionPresentationTest` | 10 | `ManualNutritionStoreTest` | 4 |
| `CompanionRuntimeTest` | 6 | `MealAnalysisTest` | 12 |
| `MotionPolicyTest` | 6 | `MealCaptureTest` | 2 |
| `PipGestureLibraryTest` | 7 | `MealEditsTest` | 10 |
| `PipIdleSchedulerTest` | 5 | `PipCompanionTest` | 3 |
| `PipMotionTest` | 12 | `AppShellTest` | 5 |
| `PipRigAssetTest` | 9 | `CoachCameraTest` | 5 |
| `PipRigSceneTest` | 8 | `CoachComposerTest` | 15 |
| `CoachHistoryWindowTest` | 7 | `CoachScreenTest` | 16 |
| `CoachReceiptPresentationTest` | 4 | `CoachVoiceTest` | 6 |
| `CoachReplyTextTest` | 1 | `MealComposerScreenTest` | 9 |
| `CoachVoiceInputTest` | 4 | `DiaryScreenTest` | 9 |
| `DiaryViewModelTest` | 4 | `ManualNutritionScreenTest` | 6 |
| `ManualNutritionDraftTest` | 5 | `MealDetailScreenTest` | 9 |
| `FoodEditTest` | 1 | `MealEditorsTest` | 7 |
| `MivuThemeTest` | 2 | `TodayScreenTest` | 10 |
| `TodayViewModelTest` | 7 | | |

## Coverage by feature

- Capture: `CoachComposerTest` covers text send, photo import (up to eight), uncertain-save reconcile, drafts and Ask
  Pip quotes. `CoachCameraTest` covers camera capture, close, recreate, a full draft and the denied permission.
  `CoachVoiceTest` and `CoachVoiceInputTest` (JVM) cover voice partial results, errors, the unavailable state, stop and
  release. `CoachWorkerTest` covers the saved turns being processed.
- Timeline and history: `CoachScreenTest` covers the empty state, the receipt, Undo, Review / Edit, question chips, the
  confirm choice, Thinking, Try again, the day choice, paging, and Jump to latest (48 dp, spoken label, drag, restore
  within 2 dp). `CoachHistoryWindowTest` and `CoachTimelineTest` cover the 100-exchange window.
- Pip: the JVM classes `PipRigAssetTest`, `PipRigSceneTest`, `PipMotionTest`, `PipGestureLibraryTest`,
  `PipIdleSchedulerTest`, `CompanionPresentationTest`, `CompanionRuntimeTest` and `MotionPolicyTest`, plus
  `PipCompanionTest` on the emulator.
- Ask Pip entry points: `DiaryScreenTest.askPipQuotesTheRecordedDay`, `MealDetailScreenTest.askPipQuotesMealAndFood`,
  `CoachComposerTest.askPipFromFoodQuotesAndPrefills`.

## Pip rig cold load

Measured once in a release build (`assembleRelease` at `e93b81b6`, signed with the debug key) on the emulator. The
timing was a temporary `Log.i` around `PipAssets.read`, made in a throwaway worktree and never committed.

- First launch after install: **1,021 ms** (reading `pip-rig.json` and `gestures.json`, then parsing every part's path
  bounds). This was on the loaded emulator, with another session's Gradle build running at the same time.
- Earlier debug-build reports were about 30 s. The review estimated 0.2–0.6 s on a real phone; no phone was measured.

## Screenshots

`docs/verification/android-coach/` holds synthetic data only, seeded with
`am instrument -e class com.yakov103.mivu.ui.today.TodayFixtureSeed#seedCoachFixture -e seedCoach empty|timeline|history`.
Each screen was captured in light, dark and font scale 2.0 (`-light`, `-dark`, `-large`):

- `coach-empty`: the first-visit state with suggestion chips.
- `coach-timeline`: a saved-food receipt with Undo and Review / Edit, a waiting message, and the latest question with
  its meal chip.
- `coach-browsing`: 30 exchanges scrolled back, with Jump to latest.
- `coach-composer-reply`: an Ask Pip "From Diary" quote, typed text and two camera photos.
- `coach-camera`: the emulator's virtual camera scene, 2 of 8 photos.
- `coach-voice`: listening, with the level bars and the red Stop.
- `today-pip`: Today with Pip.

Compared with the approved mockup (`android-design/android-coach-mockups.png`):

- Matches: the empty-state copy and chips, the receipt card, the quote card with thumbnails and "2 of 8 photos", the
  camera layout, the voice Stop, and the 48 dp Jump to latest.
- Differences, already planned:
  - The top bar shows the profile button instead of history; the history screen comes in milestone 4c.
  - The "Connect ChatGPT" footnote link is carried to 4c.
  - Thinking is not in the screenshots. The emulator is not signed in, so a waiting message shows "Connect ChatGPT
    in Settings to continue" with Try again instead. Thinking is covered by `CoachScreenTest.activityShowsThinking`.
- Differences seen:
  - The meal chip has an empty leading area where the mockup has an icon.
  - At font scale 2.0 the camera's "Choose photos" label runs under the shutter.

## Pip screen recordings (kept outside Git)

`adb shell screenrecord --time-limit 12`, on the seeded timeline:

- Coach: `/private/tmp/claude-501/-Users-yaakovkhodorkovski--claude-spares-spare-WqjKoq/1c3b4c87-cf1f-4cdf-88e2-f1b4a3b7e15b/scratchpad/pip-coach.mp4`
- Today: `/private/tmp/claude-501/-Users-yaakovkhodorkovski--claude-spares-spare-WqjKoq/1c3b4c87-cf1f-4cdf-88e2-f1b4a3b7e15b/scratchpad/pip-today.mp4`

Frame rate: not established. `ffprobe` finds one encoded frame in each file, so each recording shows a still Pip. A
12-second `dumpsys gfxinfo` window on Today, with the app resumed, counted 0 frames rendered. A recording made while
scrolling caught only 5 frames in 8 s, so the loaded emulator's encoder is also unreliable. Whether Pip idles and
blinks on this emulator is therefore unconfirmed. It needs a recheck on an idle emulator or a phone. Two things
blocked the recheck here: another session began installing and running instrumented tests on the same emulator from
17:08, and it uninstalled the app twice during the attempt.

## Not covered

- No real device: no phone frame rate, no real-phone rig load time, no Android 12 (API 31) device.
- TalkBack was not run live; accessibility is covered only by the semantics assertions in the tests.
- Live voice words: the emulator microphone is silent, so recognition of spoken words is unverified.
- No live ChatGPT turn in the UI, because the emulator is not signed in.
- Today Pip moments (saved, first meal today, day complete, welcome back, reviewed) come in milestone 7. Progress Pip
  is pending.
- No hosted CI run is claimed.
