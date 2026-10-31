# Android Coach history and replies verification

Recorded 2026-10-24. Plan: [Android Coach chat history](../superpowers/plans/2026-10-24-android-coach-history.md)
(plan 4c), milestone close.

- Source SHA tested: `60b42758ae10223d842cdf6bc4356a0f95210cd8` (branch `docs/android-design`, clean tree at the
  start of the run). During the run another session committed `eaedb236` (a plan document and a mockup, no file under
  `android/`), so the tested Android sources equal `eaedb236`.
- Environment: macOS 27.0.1, Android Studio JBR, Gradle 9.8.2; emulator `Medium_Phone_API_37.0` (emulator-5554,
  API 37). The host was heavily loaded (load average 18–28). Counts are summed from the JUnit result XML.
- Command (one run, `--rerun-tasks`):

  ```sh
  cd android && ./gradlew :app:testDebugUnitTest :app:connectedDebugAndroidTest :app:lintDebug :app:assembleRelease --rerun-tasks --continue
  ```

- Result: BUILD SUCCESSFUL in 13 min 9 s.
  - `:app:testDebugUnitTest`: 237 tests in 33 classes, 0 failed, 0 errors, 0 skipped.
  - `:app:connectedDebugAndroidTest`: 302 tests in 35 classes, 0 failed, 0 errors, 0 skipped. No seed or zero-test
    class ran: the `TodayFixtureSeed` exclusion held.
  - `:app:lintDebug`: 0 errors, 14 warnings, 1 hint. `:app:assembleRelease` passed.
  - Known flakes: `MealEditorsTest` passed 7/7 and `CoachHistoryScreenTest` (one possibly flaky test in Task 2)
    passed 11/11. No rerun was needed.
- After the docs update, `python3 scripts/ci/parity.py` passed, and
  `python3 -m unittest discover -s scripts/ci -p 'test_*.py' < /dev/null` ran 53 tests, all OK.
- Not in this run: the Task 3 review ran at the same time. Any fixes it produces are verified separately and appended
  below.

## Per-class counts

All have 0 failures, 0 errors and 0 skipped. New in this milestone: `CoachHistoryModelTest` (JVM),
`CoachSegmentsTest`, `CoachSummaryLinesTest`, `CoachHistoryScreenTest` and `CoachReplyActionsTest`.

| JVM class | Tests | Instrumented class | Tests |
|---|---|---|---|
| `AuthSessionTest` | 19 | `AppShellTest` | 5 |
| `CoachHistoryModelTest` | 4 | `ArchiveRoundTripTest` | 5 |
| `CoachHistoryWindowTest` | 7 | `CoachCameraTest` | 6 |
| `CoachReceiptPresentationTest` | 4 | `CoachComposerTest` | 18 |
| `CoachReplyCheckTest` | 2 | `CoachContextTest` | 9 |
| `CoachReplyTextTest` | 1 | `CoachEngineTest` | 11 |
| `CoachToolsTest` | 12 | `CoachHistoryScreenTest` | 11 |
| `CoachVoiceInputTest` | 4 | `CoachProgressWritesTest` | 4 |
| `CompanionPresentationTest` | 10 | `CoachReadsTest` | 4 |
| `CompanionRuntimeTest` | 6 | `CoachReplyActionsTest` | 8 |
| `DayStatusTest` | 4 | `CoachScreenTest` | 16 |
| `DiaryArchiveTest` | 7 | `CoachSegmentsTest` | 14 |
| `DiaryMathTest` | 8 | `CoachSummaryLinesTest` | 10 |
| `DiaryModelsTest` | 4 | `CoachTimelineTest` | 9 |
| `DiaryRestoreTest` | 5 | `CoachVoiceTest` | 6 |
| `DiaryValidationTest` | 21 | `CoachWorkerTest` | 8 |
| `DiaryViewModelTest` | 4 | `CoachWritesTest` | 18 |
| `FoodEditTest` | 1 | `ConnectionProofScreenTest` | 2 |
| `IdTokenValidatorTest` | 8 | `CredentialStoreTest` | 7 |
| `LoopbackCallbackTest` | 5 | `DiaryCaptureTest` | 16 |
| `ManualNutritionDraftTest` | 5 | `DiaryDatabaseTest` | 23 |
| `MivuThemeTest` | 2 | `DiaryDaysTest` | 1 |
| `MotionPolicyTest` | 6 | `DiaryQueriesTest` | 4 |
| `OAuthAttemptTest` | 12 | `DiaryScreenTest` | 9 |
| `PipGestureLibraryTest` | 7 | `ManualNutritionScreenTest` | 6 |
| `PipIdleSchedulerTest` | 5 | `ManualNutritionStoreTest` | 4 |
| `PipMotionTest` | 12 | `MealAnalysisTest` | 12 |
| `PipRigAssetTest` | 9 | `MealAnalysisWorkerTest` | 6 |
| `PipRigSceneTest` | 8 | `MealCaptureTest` | 2 |
| `ResponsesClientTest` | 12 | `MealComposerScreenTest` | 9 |
| `SampleAnalyzerTest` | 8 | `MealDetailScreenTest` | 9 |
| `SwiftJsonTest` | 8 | `MealEditorsTest` | 7 |
| `TodayViewModelTest` | 7 | `MealEditsTest` | 10 |
| | | `PipCompanionTest` | 3 |
| | | `TodayScreenTest` | 10 |

## Coverage by feature

- History and seek (`coach-history`): `CoachSegmentsTest` covers the segment index and its rebuild (a damaged turn row
  is skipped instead of failing the diary open), the day pages and date filter, stale cursors, the seek pages around a
  turn or at a day, the meal source turn, and 10,000 turns staying bounded. `CoachHistoryModelTest` (JVM) covers late
  results, Earlier ignored while loading, the error copy and invalidation.
  `CoachHistoryScreenTest` covers newest-first rows with the capture label, Earlier conversations, Choose date and Show
  all chat history, the empty copy, seek from a row, seek from a sent quote, meal Ask Pip seek, seek while paging, an
  invalid seek page, the history button's paging actions and Back. `CoachHistoryWindowTest`, `CoachTimelineTest` and `CoachScreenTest` keep the 100-exchange window and Jump to
  latest.
- Replies (`coach-reply`): `CoachReplyActionsTest` covers long-press Reply on Pip's and the person's message, Copy as
  plain text, Copy hidden for a photo-only message, swipe past the threshold, a short swipe, a vertical drag that still
  scrolls, and the Reply custom action. `CoachHistoryScreenTest.sentQuoteSeeksOriginalMessage` covers opening a sent
  quote. `CoachContextTest` resolves a quoted meal and a deleted target for the engine.
- Retake: `CoachComposerTest` (`retakeReplacesPhotoInPlace`, `failedRetakeKeepsOldPhoto`,
  `noCameraHidesCameraAndRetake`) and `CoachCameraTest.retakeModeLabelsShutterAndReturnsAfterOneShot`.
- Summary lines: `CoachSummaryLinesTest` compares undo, scale, move, photos, weight, workout, goals and day coverage
  with the iOS strings.

## Fix made during the close

- Choose date: on the first screenshot the dialog's note ("Choose the date shown in your conversation…") was drawn
  over the "Conversation date" title. The note was a sibling of `DatePicker` in the dialog content; it now sits in the
  picker's title slot under the title (`CoachHistoryScreen.kt`, commit
  `f74fb42331bb7e77a9ad945a79850765d0ca4989`). Evidence: `coach-history-date-light.png` and `-dark.png` below, taken after the fix. The text assertion in
  `CoachHistoryScreenTest.chooseDateFiltersAndShowAllClears` is unchanged; that class was not rerun after the fix
  because the emulator was unavailable (see Screenshots). The full-suite counts above are from before this commit.

## Screenshots

`docs/verification/android-coach-history/` holds synthetic data only. The seed is
`am instrument -e class com.yakov103.mivu.ui.today.TodayFixtureSeed#seedCoachFixture -e seedCoach conversations`:
five earlier conversations on separate days, then today's chat ending in a reply that quotes Pip. The APKs were built
from a clean export of `eaedb236` plus the `conversations` fixture and the date fix, because two other sessions had
uncommitted work in the same worktree.

Captured in light and dark (`-light`, `-dark`):

- `coach-history`: newest conversation first, each with its date, capture label and preview.
- `coach-history-date`: the Choose date dialog.
- `coach-seek-highlight`: Coach after tapping the oldest row, with the highlight ring on that conversation's first
  exchange.
- `coach-reply-menu`: long-press on Pip's reply, with Reply and Copy; the sent quote is visible below it.
- `coach-swipe-reply`: after a swipe on the exchange, the composer shows "Replying to Pip".

Not captured:

- Font scale 2.0 (`-large`) and `coach-retake`: blocked. After the light and dark sets, the emulator's
  `system_server` was restarted by its watchdog three times in 15 minutes (20:12–20:28, emulator load average 40,
  host 18–28). Installs failed with "Can't find service: package". Before that, another session's instrumented runs
  on the same emulator uninstalled the app several times mid-capture. Retake is covered by the tests named above.
- `coach-notification`: not built (Task 4 deferred to milestone 8).

Compared with the approved mockup (`android-design/android-coach-history-mockup.png`):

- Matches: the top bar with Navigate up and Choose date, the date headline, capture label and preview per row, the
  "Conversation date" title, the note, and Cancel / Show date.
- Differences:
  - The note sits under the dialog title; the mockup has it above the buttons (see the fix above).
  - The picker headline is the M3 default "Oct 24, 2026"; the mockup shows "Thu, Oct 23".
  - The Choose date icon uses the default action tint, not teal (parked in Task 2).
  - The seed has six conversations, so "Earlier conversations" (30 per page) does not show; it is covered by
    `CoachHistoryScreenTest.earlierConversationsLoadsNextPage`.
- Seen once, not confirmed: on a first capture attempt the keyboard opened after the swipe and the composer sat about
  500 px above it, with an empty band in between. Later captures did not open the keyboard, so this was not
  reproduced. It needs a check on a phone.

## Scope closed

- Removed from the carried items as done or cut, with the plan's reasons:
  - Summary lines: done; `CoachSummaryLinesTest` passed 10/10 against the iOS strings with no gap.
  - Photo Retake: done (above).
  - Legacy capture recovery and the `pendingMealID` prepare step: cut. Android meal captures are drained by
    `MealAnalysisWorker`, and archive import has no UI yet, so no Android user can reach that state. Revisit when
    import ships.
  - Markdown beyond emphasis: cut. iOS parses inline markdown only and the Coach prompt forbids headings, lists and
    tables; bold is handled.
- Moved to milestone 5: the model picker, the "Connect ChatGPT for replies" link and the live Phase 0 Coach turn. All
  three need the sign-in UI.
- Deferred to milestone 8: Coach reply notifications (Task 4 was not built). iOS posts them only for Siri-started
  turns, and Android has no outside-app turn source until quick capture, share or Assistant. No notification is
  claimed here. Meal-analysis notifications stay milestone 5.
- Later: `record_source`. It only fixes two invisible shortcuts, and their `shortcut:` comments stay.
- Carried from the milestone 4 close to Play readiness: Pip's frame rate needs an idle host or a real phone (the
  loaded emulator measured about 4950 ms per frame on the GPU, so this is not a regression); the meal chip's empty
  leading area; "Choose photos" under the shutter at font scale 2.0.

## Not covered

- No real device: swipe feel, the spring and the haptics were checked only with injected touches.
- TalkBack was not run live; the Reply and Copy custom actions are covered by semantics assertions only.
- The "Copied" toast on API 31–32 is untested (no device below API 33 was used).
- No live ChatGPT turn, because the emulator is not signed in.
- No hosted CI run is claimed.
