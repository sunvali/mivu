# Android iOS 1.1.1 catch-up verification

Recorded 2026-10-26. Plan: [Android iOS catch-up](../superpowers/plans/2026-10-26-android-ios-catchup.md), milestone close.
iOS baseline: `origin/main` `5afd977f` (iOS 1.1.1). The audit compared Android with every iOS PR merged after the parity
baseline `dd5e8c34`.

- Source SHA of the full run: `ab01702b6bc2457f41da53aa3bc7da4c498b08d5` (branch `docs/android-design`, clean tree).
- Fix after the run: `2a32b44a11da5d1a6e4047d40a096d1fda3d0e6c`, a test-only commit (see the unit tests below). The release
  smoke test, the `scripts/ci` tests and the parity check ran at this SHA.
- Environment:
  - macOS 27.0.1, with the Android Studio JBR and Gradle 9.8.2.
  - Emulator `Medium_Phone_API_37.0` (emulator-5554, Android 17, API 37), 1080x2400, time zone Asia/Jerusalem, Monday.
- Counting rule: counts are summed from the JUnit result XML. A skipped, assumption-stopped or zero-test class is not
  counted as passing.
- Command: one run with `--rerun-tasks`, 14:50–15:09 local time. The app was force-stopped first.

  ```sh
  cd android && ./gradlew :app:testDebugUnitTest :app:connectedDebugAndroidTest :app:lintDebug :app:assembleRelease --rerun-tasks --continue
  ```

## Result

The build failed in 18 min 59 s, on `testDebugUnitTest` only.

### `:app:testDebugUnitTest`
- 349 tests in 47 classes; 348 passed, 1 failed, 0 skipped.
- **The failure.** `TodayViewModelTest.knownAndUnknownMacros` asserted the pre-#64 rule ("one unknown protein makes the
  total unknown"). Task 1 changed `sumOrNull` but missed this class.
- **The fix.** `2a32b44a` expects "31 g", the known protein, while the unknown note still shows. This is the iOS #64
  behaviour, and Today's screen test `unknownProteinShowsDashAndNote` already matched it.
- **Rerun.** `TodayViewModelTest` 7/7 at `2a32b44a`.
- **Per class.** All passed unless noted:
  - AuthSessionTest 19, BackupRulesTest 2, ChatGPTConnectionTest 17, CoachFailureReasonTest 2, CoachHistoryModelTest 4,
    CoachHistoryWindowTest 7, CoachReceiptPresentationTest 5, CoachReplyCheckTest 2, CoachReplyLinesTest 1,
    CoachReplyNotificationTest 7, CoachReplyTextTest 1, CoachReportsTest 1, CoachToolsTest 12, CoachVoiceInputTest 4.
  - CompanionPresentationTest 18, CompanionRuntimeTest 7, DayStatusTest 4, DiaryArchiveTest 10, DiaryMathTest 9,
    DiaryModelsTest 4, DiaryReportTest 5, DiaryRestoreTest 8, DiaryValidationTest 21, DiaryViewModelTest 4,
    FoodEditTest 1, GoalEditorValuesTest 5, IdTokenValidatorTest 8, LoopbackCallbackTest 5.
  - ManualNutritionDraftTest 5, MivuThemeTest 2, MorningReminderTest 3, MotionPolicyTest 5, OAuthAttemptTest 12,
    OnboardingTargetsTest 6, PipGestureLibraryTest 8, PipIdleSchedulerTest 5, PipLineTest 6, PipMotionTest 12,
    PipRigAssetTest 9, PipRigSceneTest 10, ProgressInsightsTest 32, ResponsesClientTest 12, SampleAnalyzerTest 8.
  - SwiftJsonTest 8, TodayViewModelTest 6 of 7 (7/7 on rerun), WakingDayInstructionTest 1, WidgetSnapshotTest 5.

### `:app:connectedDebugAndroidTest`
- 508 tests in 56 classes; 506 passed and 2 stopped on their assumption ("permission already granted on this install").
  Neither is counted:
  - `MorningCheckInTest.deniedNotificationPermissionExplainsTheOffSwitch` (12 of 13);
  - `ShareToCoachTest.deniedPermissionPostsNothingAndSaves` (9 of 10).
- Both are the known carried item. The full suite always holds the notification grant.
- **Per class.** All passed unless noted:
  - AppBackgroundTest 2, AppIconTest 2, AppShellTest 5, ArchiveRoundTripTest 12, BackupExportScreenTest 14,
    CaloriesWidgetTest 9, CoachCameraTest 7, CoachComposerTest 26, CoachContextTest 9, CoachEngineTest 18,
    CoachHistoryScreenTest 11, CoachJobServiceTest 5, CoachProgressWritesTest 4, CoachReadsTest 4.
  - CoachReplyActionsTest 14, CoachReplyFollowTest 3, CoachScreenTest 22, CoachSegmentsTest 14,
    CoachSummaryLinesTest 10, CoachTimelineTest 11, CoachVoiceTest 6, CoachWorkerTest 15, CoachWritesTest 18,
    ConnectionProofScreenTest 2, ConnectionScreenTest 12, CredentialStoreTest 7, DiaryCaptureTest 16.
  - DiaryDatabaseTest 23, DiaryDaysTest 6, DiaryQueriesTest 4, DiaryReportPdfTest 2, DiaryScreenTest 9, EditorsTest 10,
    ManualNutritionScreenTest 6, ManualNutritionStoreTest 4, MealAnalysisTest 12, MealAnalysisWorkerTest 6,
    MealCaptureTest 2, MealComposerScreenTest 9, MealDetailScreenTest 11, MealEditorsTest 7, MealEditsTest 10.
  - MorningCheckInTest 12 of 13, MorningReminderReceiverTest 4, OnboardingScreenTest 16, PipCompanionTest 3,
    PlanWelcomeTest 2, ProgressQueriesTest 8, ProgressScreenTest 9, QuickCaptureTest 9, ReleaseSmokeTest 6 (debug),
    ReviewedOriginTest 2, ShareToCoachTest 9 of 10, TellCoachTest 8, TodayCompanionTest 5, TodayScreenTest 14.
- **No flaky failures this run.** `EditorsTest` (10/10), `CoachHistoryScreenTest.mealAskPipSeeksSourceTurn` and
  `TodayScreenTest.logWithPipSelectsCoach` all passed.

### `:app:lintDebug`
- 0 errors, 37 warnings and 1 hint. The milestone 7 record had 23 warnings.
- The warnings are:
  - 15 `UseKtx`, 8 `HardcodedText`;
  - 3 `NewerVersionAvailable`, 3 `UselessLeaf`;
  - 1 each of `ApplySharedPref`, `GradleDependency`, `NotShrinkingResources`, `VectorPath` and `VisibleForTests`.
- None is an error. This milestone did not triage them.

### Release and scripts
- **`:app:assembleRelease`:** passed (`app-release-unsigned.apk`).
- **Release smoke:** passed at `2a32b44a`, `ReleaseSmokeTest` 6/6 on the minified release build. Command:

  ```sh
  ./gradlew :app:connectedReleaseAndroidTest -Pmivu.testBuildType=release -Pandroid.testInstrumentationRunnerArguments.class=com.yakov103.mivu.release.ReleaseSmokeTest
  ```

- **Parity:** `python3 scripts/ci/parity.py` passed after the parity changes in this commit.
- **`scripts/ci` tests:** `python3 -m unittest discover -s scripts/ci -p 'test_*.py' < /dev/null` ran 57 tests OK.

## Named tests by iOS PR (all passed in the run above)

- **#58, auto-closed days.** `DayStatusTest` 4/4 and `DiaryDaysTest` 6/6 cover Open, Closed and Skipped and the
  waking day. Skip and Count This Day are in the earlier records.
- **#59, short checked replies.** `CoachReplyCheckTest` 2/2, `CoachReplyTextTest` 1/1, `CoachScreenTest` 22/22.
- **#64, known nutrient values add up.**
  - `DiaryMathTest` 9/9 (`unknownComponentsAddNothingAndAreCounted`, `dailyAddsKnownSubtotals`).
  - `CoachReceiptPresentationTest` 5/5 (`committedMacrosAddOnlyKnownValues`).
  - `ProgressInsightsTest` 32/32 and `TodayViewModelTest` 7/7.
- **#66, correction and silent retry.**
  - `CoachEngineTest` 18/18, which includes `lostStateWriteKeepsTheSharedErrorClean`.
  - `CoachFailureReasonTest` 2/2.
  - `DiaryArchiveTest` 10/10: `failureReason` round-trips and is capped at 200 UTF-8 bytes.
  - `ArchiveRoundTripTest` 12/12.
- **#67 and #70, Pip's bubble and day chip.** `PipLineTest` 6/6 (the six iOS `PipLineTests`), `CoachComposerTest` 26/26
  and `CoachHistoryScreenTest` 11/11 (friendly dates and the zone suffix).
- **#45, a workout quote opens the workout.** `CoachScreenTest.workoutQuoteOpensTheWorkout`.
- **#46, the composer floats over the chat.**
  - `CoachScreenTest.timelineScrollsBehindTheComposer`, `newestReplyStaysAboveTheKeyboard`,
    `jumpToLatestIs48dpWithSpokenLabel` and `dragOnJumpToLatestScrollsTimeline`.
  - Typing gaze follows the caret to the end of the last line, as iOS `caretSignal` does.
    - `CoachComposer` reports the caret's place (0–60), and `CompanionPresentation` maps it to Pip's gaze
      (`CompanionPresentationTest` 18/18).
    - No test pins the caret measure itself.
- **#69, Power Saver keeps Pip moving.** `MotionPolicyTest` 5/5. Only Remove animations and severe heat or worse hold
  Pip still.
- **#71, no turn left on Thinking.** `CoachWorkerTest` 15/15 and `CoachJobServiceTest` 5/5.
- **#75, setup targets on the waking day.** `OnboardingScreenTest` 16/16, from commit
  `fd4fd30653fd6312cff48ea0c8fef2c9b8abf658`.
- **Pip and Today.** `CompanionRuntimeTest` 7/7, `PipGestureLibraryTest` 8/8, `TodayCompanionTest` 5/5 and
  `ReviewedOriginTest` 2/2.

## Screenshots

`docs/verification/android-ios-catchup/` holds synthetic data only.
- **How they were taken.**
  - A temporary instrumented test, deleted afterwards and not committed, seeded each state through the real store.
  - Coach states use the same harness as `CoachComposerTest`: `CoachScreen` on the theme background, with
    `connected` set by the test.
  - History and Today run the whole `MivuApp`.
  - Each shot waits until Pip's rig is composed. In a cold process the rig takes several seconds to load on this
    emulator, and the composer keeps his space meanwhile.
- **Variants.** Light (`-light`), dark (`-dark`) and system font scale 2.0 (`-large`). Font scale and night mode were
  reset afterwards to 1.0 and "no", and the app was force-stopped.

| Shot | State |
|---|---|
| `coach-idle` | Connected, one meal logged: "Anything else to log?" and "Today · 380 / 2,100 kcal". At 2.0 the greeting hides by design. |
| `coach-working-partial` | A saved meal with a food that has no calories, plus a captured turn: "Thinking…" in the timeline and "Counting that up…" in the bubble. The chip reads "Today · 640+ / 2,100 kcal" (spoken "at least 640"). |
| `coach-needs-retry` | A failed turn: the timeline row's Try again, plus Pip's recovery pose with "That one didn’t go through." and Try again. |
| `coach-not-connected` | No connection: the bubble offers Connect, there is no plan footnote, and the starters show over an empty chat. |
| `coach-scrolled-behind` | 30 exchanges scrolled up: rows pass behind the faded composer band, and Jump to latest sits above it. |
| `history-rows` | Chat history: "Today", "Yesterday", then "Oct 24"… with a short time per row (default zone, so no suffix). |
| `today-partial-macros` | One food has unknown protein: protein shows the known 42 g, with "Some nutrients are unknown. Recorded totals may be incomplete." (#64). |

Compared with the approved mockup (`catchup-mockup`, iOS 1.1.1 #67 and #70):
- **Matches.**
  - The bubble sits beside Pip and over the round button's column, with an asymmetric corner nearest Pip.
  - The chip is a summary capsule with "+" for a partial figure.
  - Try again sits in the bubble on a failed turn, and Connect in the not-connected bubble.
  - The plan footnote shows only when connected.
- **Differences.**
  - The data differs, because receipt cards were not seeded.
  - "Looking at your photo…" was not shot; it needs a send with photos.
  - Power Saver motion and thermal behaviour are `blocked` on the emulator, as on the iOS simulator. They need a
    physical phone (carried).

## Limits
- **One full run.** It used `ab01702b`. Only `TodayViewModelTest` was rerun after the test-only fix. The full suites
  were not rerun at `2a32b44a`.
- **Assumption stops.** The two permission-denied tests still stop on their assumption in a full run. This is carried.
- **#72, the meal notification's "At least N kcal".** `n/a` until Android has a meal-analysis notification. Carried.
- **#49 and #50.** The on-device fallback and profile delete stay `pending` as owner decisions.
- **Not checked.** TalkBack on the day chip, and the bubble's feel on a real device.
