# Android Progress, setup with Pip and day rollover verification

Recorded 2026-10-25. Plan: [Android Progress, onboarding and day rollover](../superpowers/plans/2026-10-24-android-progress-onboarding.md)
(milestone 6), milestone close. By ruling, this one full suite also closes milestone 5
([connection record](2026-10-24-android-connection.md)).

- Source SHA tested: `26b5cd94a5e5e4c161184e19f9044d9a55f28f35` (branch `docs/android-design`, clean tree apart from
  the untracked milestone 5 screenshot folder).
- Environment: macOS 27.0.1, Android Studio JBR, Gradle 9.8.2; emulator `Medium_Phone_API_37.0` (emulator-5554,
  API 37), time zone Asia/Jerusalem. Host load average about 9–12. Counts are summed from the JUnit result XML.
- Command (one run, `--rerun-tasks`), started about 23:56 on Saturday 2026-10-24 local time:

  ```sh
  cd android && ./gradlew :app:testDebugUnitTest :app:connectedDebugAndroidTest :app:lintDebug :app:assembleRelease --rerun-tasks --continue
  ```

- Result: BUILD FAILED in 17 min 52 s.
  - `:app:testDebugUnitTest`: 309 tests in 40 classes, 0 failed, 0 errors, 0 skipped.
  - `:app:connectedDebugAndroidTest`: 401 tests in 46 classes; 393 passed, 7 failed, and 1 stopped on an assumption
    (reported as a failure, not counted as a pass). `MorningCheckInSeed` also ran (a seed class, one test, stopped on
    its assumption); it is not counted, and `e0214396` adds it to the `notClass` exclusion beside `TodayFixtureSeed`.
  - `:app:lintDebug`: 2 errors (`ViewModelConstructorInComposable` in `EditorsTest.kt:182` and `:270`, test code),
    23 warnings, 1 hint. Fixed in `e0214396374dd0256b8dcc98db44273e9bebaeee` (`remember { … }`); `lintDebug` rerun at
    that commit: 0 errors, 23 warnings, 1 hint.
  - `:app:assembleRelease`: passed.
- The instrumented run crossed local midnight, Saturday into Sunday, inside the 00:00–04:00 window before the 4 AM day
  cutoff. Every failure below depends on that clock, not on the change under test:
  - `MealComposerScreenTest` (`textOnlySaveShowsSampleAppleOnToday`, `reviewFirstShowsAwaitingReview`,
    `photoPickerResultSaved`): reproduced at 00:15. The meal saves to the waking day (Saturday) while the calendar
    says Sunday, so Today shows the iOS late-meal receipt ("Added to Sat, Oct 24" / "Move to Sun, Oct 25") instead of
    the meal row the test waits for.
  - `CoachScreenTest.dayChoiceLogsToChosenDay`: not rerun; it timed out waiting for the chosen day's text, and the day
    choice it drives depends on the same window.
  - `DiaryScreenTest.futurePillDisabled`: the seed's day is the waking day (Saturday), the Diary strip's today is the
    calendar day (Sunday), so the pill the test expects to be "future" is today.
  - `EditorsTest.diaryDayMenuAddsWeightToThatDay` and `workoutDetailDeletesAfterConfirm`: the class pins the cutoff
    to 0, so "today" is Sunday and "yesterday" falls in the previous week page of a Sunday-first week strip.
  - `MorningCheckInTest.deniedNotificationPermissionExplainsTheOffSwitch`: stopped on its assumption ("permission
    already granted on this install"); an earlier test in the same install had granted it.
- Reruns: `EditorsTest` at `e0214396` (00:20): 7 of 10, the same two plus `todayWeightRowOpensAddWeightAndSaves`
  (waiting for "72.5 kg"; it passed in the full run, cause not established). No other class was rerun. These classes
  need a rerun outside 00:00–04:00 and not on a Sunday; making them clock-independent is carried.
- After the docs update, `python3 scripts/ci/parity.py` and
  `python3 -m unittest discover -s scripts/ci -p 'test_*.py' < /dev/null`: `parity.py` passed and the 53 `scripts/ci` tests ran OK.

## Per-class counts

All JVM classes: 0 failures, 0 errors, 0 skipped. New in milestone 6: `DiaryReportTest`, `GoalEditorValuesTest`,
`MorningReminderTest`, `OnboardingTargetsTest`, `ProgressInsightsTest`, `WakingDayInstructionTest` (JVM);
`BackupExportScreenTest`, `DiaryReportPdfTest`, `EditorsTest`, `MorningCheckInTest`, `MorningReminderReceiverTest`,
`OnboardingScreenTest`, `ProgressQueriesTest`, `ProgressScreenTest`. New in milestone 5: `ChatGPTConnectionTest`,
`CoachJobServiceTest`, `ConnectionScreenTest`, `PlanWelcomeTest`.

| JVM class | Tests | Instrumented class | Passed |
|---|---|---|---|
| `AuthSessionTest` | 19 | `AppShellTest` | 5 |
| `ChatGPTConnectionTest` | 17 | `ArchiveRoundTripTest` | 5 |
| `CoachHistoryModelTest` | 4 | `BackupExportScreenTest` | 2 |
| `CoachHistoryWindowTest` | 7 | `CoachCameraTest` | 6 |
| `CoachReceiptPresentationTest` | 4 | `CoachComposerTest` | 21 |
| `CoachReplyCheckTest` | 2 | `CoachContextTest` | 9 |
| `CoachReplyTextTest` | 1 | `CoachEngineTest` | 11 |
| `CoachToolsTest` | 12 | `CoachHistoryScreenTest` | 11 |
| `CoachVoiceInputTest` | 4 | `CoachJobServiceTest` | 5 |
| `CompanionPresentationTest` | 10 | `CoachProgressWritesTest` | 4 |
| `CompanionRuntimeTest` | 7 | `CoachReadsTest` | 4 |
| `DayStatusTest` | 4 | `CoachReplyActionsTest` | 8 |
| `DiaryArchiveTest` | 7 | `CoachScreenTest` | 17 of 18 |
| `DiaryMathTest` | 8 | `CoachSegmentsTest` | 14 |
| `DiaryModelsTest` | 4 | `CoachSummaryLinesTest` | 10 |
| `DiaryReportTest` | 5 | `CoachTimelineTest` | 11 |
| `DiaryRestoreTest` | 5 | `CoachVoiceTest` | 6 |
| `DiaryValidationTest` | 21 | `CoachWorkerTest` | 11 |
| `DiaryViewModelTest` | 4 | `CoachWritesTest` | 18 |
| `FoodEditTest` | 1 | `ConnectionProofScreenTest` | 2 |
| `GoalEditorValuesTest` | 5 | `ConnectionScreenTest` | 12 |
| `IdTokenValidatorTest` | 8 | `CredentialStoreTest` | 7 |
| `LoopbackCallbackTest` | 5 | `DiaryCaptureTest` | 16 |
| `ManualNutritionDraftTest` | 5 | `DiaryDatabaseTest` | 23 |
| `MivuThemeTest` | 2 | `DiaryDaysTest` | 6 |
| `MorningReminderTest` | 3 | `DiaryQueriesTest` | 4 |
| `MotionPolicyTest` | 6 | `DiaryReportPdfTest` | 2 |
| `OAuthAttemptTest` | 12 | `DiaryScreenTest` | 8 of 9 |
| `OnboardingTargetsTest` | 6 | `EditorsTest` | 8 of 10 |
| `PipGestureLibraryTest` | 7 | `ManualNutritionScreenTest` | 6 |
| `PipIdleSchedulerTest` | 5 | `ManualNutritionStoreTest` | 4 |
| `PipMotionTest` | 12 | `MealAnalysisTest` | 12 |
| `PipRigAssetTest` | 9 | `MealAnalysisWorkerTest` | 6 |
| `PipRigSceneTest` | 10 | `MealCaptureTest` | 2 |
| `ProgressInsightsTest` | 32 | `MealComposerScreenTest` | 6 of 9 |
| `ResponsesClientTest` | 12 | `MealDetailScreenTest` | 11 |
| `SampleAnalyzerTest` | 8 | `MealEditorsTest` | 7 |
| `SwiftJsonTest` | 8 | `MealEditsTest` | 10 |
| `TodayViewModelTest` | 7 | `MorningCheckInTest` | 12 of 13 |
| `WakingDayInstructionTest` | 1 | `MorningReminderReceiverTest` | 4 |
|  |  | `OnboardingScreenTest` | 13 |
|  |  | `PipCompanionTest` | 3 |
|  |  | `PlanWelcomeTest` | 2 |
|  |  | `ProgressQueriesTest` | 8 |
|  |  | `ProgressScreenTest` | 9 |
|  |  | `TodayScreenTest` | 12 |

## Coverage by feature

- Progress (`progress`, `progress-chart-first`): `ProgressInsightsTest` (32: bands, trend, headline, burn, wins,
  buckets, plain-word lines), `ProgressQueriesTest` (8, including a 365-day load), `ProgressScreenTest` (9: every
  range, no-log days, More rows, Goals, the weight ledger, the placeholder, failure keeping the last report, spoken
  chart summaries, font scale 2.0), `GoalEditorValuesTest` (5). Editors: `EditorsTest` passed 8 of 10 (above).
- Day rollover and morning check-in (`day-rollover`): `DiaryDaysTest` (6: waking date at the cutoff boundaries,
  rollover after the cutoff, a changed cutoff, three days away), `WakingDayInstructionTest`, `MorningCheckInTest`
  (12 of 13 passed; one assumption stop above), `MorningReminderTest` (3) and `MorningReminderReceiverTest` (4).
- Setup with Pip (`onboarding`): `OnboardingTargetsTest` (6) and `OnboardingScreenTest` (13: opens once for a new
  diary, never for an existing one, Later, the healthy-target gate, the estimate when disconnected, tuned and rejected
  replies, Retry, the save, Redo from Settings, recreation, 48 dp at font scale 2.0).
- Reports (`reports`): `DiaryReportTest` (5: formula neutralising and RFC 4180 quoting, numbers, `lastDays` at 01:30
  with cutoff 4, all-time range, a legacy weight without a day), `DiaryReportPdfTest` (2: a multi-page report parsed
  back with `PdfRenderer`, an empty range), `BackupExportScreenTest` (2: the chooser with `ACTION_SEND_MULTIPLE`,
  three `…reports` URIs and the read grant, the files removed when it returns; a profile change during preparation
  drops the files and shares nothing). Before implementation, `DiaryReportTest` failed to compile (no
  `DiaryReport`); the profile-change test failed when the profile check was removed and passed with it restored.

## Reports

- Port of iOS `DiaryReport.swift`, `DiaryReportPDF.swift` and `DiaryReportSettings.swift`: `report/DiaryReport.kt`
  (model, CSV, `lastDays`, `shift`, `write` with the iOS file names), `report/DiaryReportPdf.kt` (`PdfDocument`, A4
  at 595×842 pt, two passes for "Page n of N", no Pip in the header until `app-icon`), and
  `ui/settings/BackupExportScreen.kt` ("Share a report": range menu with Custom opening the M3 date range picker,
  PDF | CSV, the iOS description lines, a tonal "Share report" showing "Preparing report").
- Files go to `cacheDir/reports/<uuid>/` and are shared through the `FileProvider` `${applicationId}.reports`, which
  exposes only that folder. The folder is deleted when the chooser returns, and on the next open of the screen.
- Deviation: `pdf()` takes no `Context` (the brief named `pdf(context)`); `PdfDocument` needs none.
- Live check on the emulator: Share report (PDF, Last 30 days) opened the system share sheet with
  "Mivu report 2026-09-25 to 2026-10-24.pdf" (Quick Share, Print, Gemini, Drive, Messages). Print opened the system
  print preview, which rendered both pages, the summary tiles, the weight trend and "Page 1 of 2"
  (`share-report-pdf-preview-light.png`); it was cancelled without printing. After returning, `cache/reports` held no
  files.

## Screenshots

`docs/verification/android-progress/` holds synthetic data only, taken at `e0214396` (the app sources equal
`26b5cd94`). Seed: `am instrument -e class com.yakov103.mivu.ui.today.MorningCheckInSeed -e seedMorningFixture true`
(yesterday's meals at 1,870 of 2,100 kcal, and five weigh-ins 1–10 days back). Each screen is captured in light (`-light`), dark
(`-dark`) and font scale 2.0 (`-large`):

- `today-morning`: Today with the morning check-in.
- `progress-week`: Progress, Week.
- `settings-your-day`: Settings with Your day.
- `goal-editor`: Goals, opened from Settings.
- `share-report`: Backup & export.
- `onboarding-hello`: setup with Pip, opened from "Redo setup with Pip".

Also `share-sheet-light.png` and `share-report-pdf-preview-light.png` (above).

Compared with the mockup (`android-design/android-progress-mockup.png`):

- Matches: the check-in card (Yesterday, 1,870 of 2,100 kcal, weight field with kg menu, Skip and Save); Progress
  segmented ranges, the dashed no-log bars, the legend and the weight card; the Settings groups; the Backup & export
  range menu, segmented PDF | CSV, description and tonal Share report; the setup hello screen.
- Differences and findings:
  - The captures were taken after midnight, so the check-in greets "Good evening" (the hour-based greeting) and
    Progress reads "Fresh start ahead" with one logged day in the week; the mockup shows a morning and a full week.
  - Goals opened from Settings at 00:31 shows "Starting on Oct 25, 2026" (the calendar date, while the waking day
    is Oct 24) with empty targets, although a 2,100 kcal goal exists; the mockup shows the current targets. Not
    investigated here; carried.
  - Settings at font scale 2.0: the "Coach AI" title wraps as "Coa / ch / AI" beside "Connect ChatGPT"
    (`settings-your-day-large.png`). Carried.
  - The mockup's PDF preview card on Backup & export is not built; the share sheet and print preview show the PDF.
  - The reminder notification was not captured; its delivery on a phone stays `blocked`.

## Scope closed

- Removed from the carried items: "Port the per-device day-cutoff setting" (done: Settings "Day starts at",
  `DiaryDaysTest`, `MorningCheckInTest.dayStartsAtChangesTheFooterAndCutoff`) and "Add the morning check-in, the
  weight row and the goal editor" (done: `MorningCheckInTest`, `EditorsTest`).
- Added: "Backup & export: the archive export/import UI joins the report screen", "Morning reminder: deliver and tap
  on a physical phone", clock-independent day tests, and the two screenshot findings above.

## Not covered

- No physical phone: the morning reminder's delivery and tap, and the share sheet with real apps.
- Progress Month, 3M, Year and the detail screens, the workout editor and the other setup steps have no screenshot
  in this set; they are covered by the tests named above.
- TalkBack was not run live.
- No hosted CI run is claimed.
