# Android widgets, share and backup verification

Recorded 2026-10-25. Plan: [Android widgets, share and backup](../superpowers/plans/2026-10-25-android-widgets-share-backup.md)
(milestone 8), milestone close.

- Source SHA of the full run: `bed7cea8533da9a0272a47b0255f3a944022912b` (branch `docs/android-design`, clean tree).
  Two small commits followed it, each with focused reruns below:
  `e7ea452bf64de3f5c8168b88c50e7bd639fa8639` (test isolation) and `238f623acbb4edf579bd090d1e6b3945aae8d985`
  (export space check).
- Environment: macOS 27.0.1, Android Studio JBR, Gradle 9.8.2; emulator `Medium_Phone_API_37.0` (emulator-5554,
  API 37, `dalvik.vm.heapgrowthlimit=192m`), time zone Asia/Jerusalem, Sunday. Counts are summed from the JUnit result
  XML; a skipped, assumption-stopped or zero-test class is not counted as passing.
- Command (one run, `--rerun-tasks`), 20:40–20:58 local time:

  ```sh
  cd android && ./gradlew :app:testDebugUnitTest :app:connectedDebugAndroidTest :app:lintDebug :app:assembleRelease --rerun-tasks --continue
  ```

- Result: BUILD FAILED in 17 min 37 s (`connectedDebugAndroidTest` only).
  - `:app:testDebugUnitTest`: 333 tests in 42 classes, 0 failed, 0 skipped.
  - `:app:connectedDebugAndroidTest`: 469 tests in 54 classes; 452 passed, 17 failed:
    - `ShareToCoachTest` (0 of 10) and `CoachReplyFollowTest` (0 of 3): test isolation. Each class's `@BeforeClass`
      deletes the diaries and creates a fresh one, but `@Before` reused the process-wide repository's earlier
      `Ready` state, so it wrote through a connection to the deleted file (`SQLITE_READONLY_DBMOVED`; the reply tests
      saw `TellCoach` return `Failed`). Fixed in `e7ea452b`: each `@Before` now calls `bootstrap()`. The classes in
      full-suite order (`CoachJobServiceTest` through `ShareToCoachTest`, 11 classes, `am instrument`) then ran 73
      tests with 1 failure, `deniedPermissionPostsNothingAndSaves`, which asserted the notification permission was
      never granted although an earlier class grants it. It now stops on an assumption, as
      `MorningCheckInTest.deniedNotificationPermissionExplainsTheOffSwitch` does, so it is not counted in a full run.
    - `MorningReminderReceiverTest.alarmPostsTheMorningNotification` (3 of 4): no notification posted. It passed in
      the same ordered rerun above; not reproduced.
    - `CoachCameraTest.recreateMidCaptureKeepsDraft` (5 of 6) and `MealEditorsTest.scaleToTargetUpdatesFoods`
      (6 of 7): timeouts. Both classes passed 13 of 13 when rerun together. Flaky waits, not counted as passes.
    - `MorningCheckInTest.deniedNotificationPermissionExplainsTheOffSwitch` (12 of 13): assumption stop
      ("permission already granted on this install"), as in earlier records.
  - `:app:lintDebug`: 0 errors, 37 warnings, 1 hint. One was new in this task (`UsableSpace` in
    `BackupExportScreen.kt`); `238f623a` checks space with `StorageManager.getAllocatableBytes`, as iOS checks
    "available for important usage", leaving 36 warnings. The others come from earlier tasks (widget `HardcodedText`
    and `UselessLeaf`, `MissingApplicationIcon`, `UseKtx`) or earlier milestones.
  - `:app:assembleRelease`: passed.
- `python3 scripts/ci/parity.py` passed, and `python3 -m unittest discover -s scripts/ci -p 'test_*.py' < /dev/null`
  ran 53 tests OK.

## Per-class counts (full run, connected)

AppBackgroundTest 2/2, AppShellTest 5/5, ArchiveRoundTripTest 10/10, BackupExportScreenTest 13/13,
CaloriesWidgetTest 9/9, CoachCameraTest 5/6, CoachComposerTest 21/21, CoachContextTest 9/9, CoachEngineTest 11/11,
CoachHistoryScreenTest 11/11, CoachJobServiceTest 5/5, CoachProgressWritesTest 4/4, CoachReadsTest 4/4,
CoachReplyActionsTest 8/8, CoachReplyFollowTest 0/3, CoachScreenTest 18/18, CoachSegmentsTest 14/14,
CoachSummaryLinesTest 10/10, CoachTimelineTest 11/11, CoachVoiceTest 6/6, CoachWorkerTest 11/11,
CoachWritesTest 18/18, ConnectionProofScreenTest 2/2, ConnectionScreenTest 12/12, CredentialStoreTest 7/7,
DiaryCaptureTest 16/16, DiaryDatabaseTest 23/23, DiaryDaysTest 6/6, DiaryQueriesTest 4/4, DiaryReportPdfTest 2/2,
DiaryScreenTest 9/9, EditorsTest 10/10, ManualNutritionScreenTest 6/6, ManualNutritionStoreTest 4/4,
MealAnalysisTest 12/12, MealAnalysisWorkerTest 6/6, MealCaptureTest 2/2, MealComposerScreenTest 9/9,
MealDetailScreenTest 11/11, MealEditorsTest 6/7, MealEditsTest 10/10, MorningCheckInTest 12/13,
MorningReminderReceiverTest 3/4, OnboardingScreenTest 15/15, PipCompanionTest 3/3, PlanWelcomeTest 2/2,
ProgressQueriesTest 8/8, ProgressScreenTest 9/9, QuickCaptureTest 9/9, ReviewedOriginTest 2/2, ShareToCoachTest 0/10,
TellCoachTest 8/8, TodayCompanionTest 5/5, TodayScreenTest 14/14.

Unit (all passed): includes WidgetSnapshotTest 5/5, CoachReplyNotificationTest 7/7, DiaryArchiveTest 7/7,
DiaryRestoreTest 8/8, SwiftJsonTest 8/8.

## Named tests

Widgets (Task 2): `CaloriesWidgetTest` 9/9, `WidgetSnapshotTest` 5/5 (rolloverEntryShowsZeroAfterCutoff,
nextRolloverUsesTheDaysZone).

Quick capture (Task 1): `QuickCaptureTest` 9/9, `AppShellTest` 5/5.

Share and reply notification (Tasks 3–4): `TellCoachTest` 8/8 in the full run. `ShareToCoachTest` and
`CoachReplyFollowTest` failed in the full run on test isolation (above); after `e7ea452b` the ordered rerun passed
`ShareToCoachTest` 9 of 10 (deniedPermissionPostsNothingAndSaves needs a fresh install; now an assumption) and
`CoachReplyFollowTest` 3/3 (noNotificationWhileMivuIsOnScreen, backgroundReplyPostsOnceAndOpensCoach,
stoppedJobPostsTheSavedNote). `CoachReplyNotificationTest` 7/7 (unit).

Archive (Tasks 5–6):
- `BackupExportScreenTest` 13/13 in the full run, and 13/13 again at `238f623a`: exportWritesAnArchiveThatDecodes,
  cancelledExportSavesNothing, restoreAsksThenReplaces (the iOS "(N meals)" message; Cancel deletes the spool),
  successorReplacesTheDiary, staleArchiveLeavesTheDiaryUntouched, deletedMealIsNotResurrected,
  otherLocalProfileIsRefused, newProfileImportsAndSwitches, garbageFileSaysCouldNotRead, rowsAre48dpAtFontScale2, and
  the three report tests.
- `ArchiveRoundTripTest` 10/10 in the full run (the 120 MB tests return early without `measureMemory`), and 10/10 at
  `bed7cea8` with `-Pandroid.testInstrumentationRunnerArguments.measureMemory=true`:
  - importHundredTwentyMegabytesOverADiary: 55.3 s, archive 160,018,828 bytes, Java live peak delta 51.9 MB, native
    12.3 MB, 8.3 s for the import;
  - exportHundredTwentyMegabytes: 23.6 s, archive 160,018,867 bytes, Java live peak delta 100.0 MB, native 10.0 MB,
    4.6 s for the export (heap limit 201,326,592 bytes);
  - androidExportStillMatchesFixture (byte comparison restored), exportLetsWritesInBetweenPhotos,
    photoGoneDuringExportFailsIt, iosFixtureStillImports, failedImportRemovesTheSpool.
- `DiaryRestoreTest` 8/8 and `DiaryArchiveTest` 7/7 (unit).
- iOS reads the regenerated Android fixture: `xcodebuild test -project ios/Mivu.xcodeproj -scheme Mivu -testPlan Mivu
  -destination id=42CE2315-9339-4EF1-A5B4-064444D0FA44 -only-testing:MivuTests/ArchiveFixtureTests
  -collect-test-diagnostics never` at `bed7cea8`, iPhone 17 Pro simulator: `ArchiveFixtureTests` 2/2
  (androidFixtureDecodesToSyntheticSnapshot, fixturesMatchSyntheticSnapshot), TEST SUCCEEDED.

RED evidence: before the implementation, `ArchiveRoundTripTest` ran 10 tests with 3 failures
(androidExportStillMatchesFixture: the stale golden's `8.0E8`; exportLetsWritesInBetweenPhotos and
photoGoneDuringExportFailsIt: "nested diary transaction"). The new `BackupExportScreenTest` did not compile against the
old screen (no repository parameter, no archive rows).

## Golden fixture

`fixtures/archive/android-v4-full.json` was written before plain-decimal dates (`b700319c`) and held exponent numbers
such as `"startAt":8.0E8`. It was regenerated with `ArchiveRoundTripTest.writeAndroidFixture` (`am instrument -e
writeFixtures true`, then `adb exec-out run-as com.yakov103.mivu cat files/android-v4-full.json`): no exponent form
remains, and it parses to the same JSON value as `ios-v4-full.json`. `androidExportStillMatchesFixture` compares the
streamed export with it byte for byte again, and iOS decodes it (above).

## Decisions

- **Export lock.** `withPhotoDigests` reads the snapshot (with photo digests) in one write transaction, then reads
  each photo's bytes in its own short transaction and checks its SHA-256 against the snapshot. A capture during an
  export now waits for one photo, not the whole 4–5 s encode. A photo deleted or changed meanwhile fails the export
  ("Could not prepare an export…") rather than writing a mixed archive. A plain read transaction would not have
  helped: in `DELETE` journal mode the single connection is held for the whole transaction either way.
- **Restore keeps the decoded spool until the dialog answers.** The archive is decoded once into
  `cacheDir/archive-<uuid>`, the dialog shows the iOS copy, and "Restore diary" applies it through `replacement`
  (same profile) or `DiaryRepository.importProfile(incoming, spool)` (unknown profile). The plan's
  `importProfile(input, cacheDir)` signature would have decoded the file a second time. Cancel, dismissal and leaving
  the screen delete the spool. A stale, resurrecting or unreadable archive shows "Could not read this diary archive.
  Your local diary is preserved." and changes nothing.
- **Switching to an imported profile** runs on the app scope (`MivuApp`), so the switch is not cancelled when the
  screen leaves. On the emulator the app stayed on Backup & export, now for the imported diary, as iOS stays in
  Settings; there is no "restored" line, as on iOS.
- **Export** writes `cacheDir/exports/<uuid>/archive.json` first (with the iOS capacity rule: five times the diary
  file plus 64 KiB), then opens `CreateDocument` with "Mivu-private-diary.json", then copies with
  `openOutputStream(uri, "wt")`. The folder is deleted after the copy, on cancel and failure, and on the next screen
  open. A profile change during preparation drops the file.
- The footnote says the file can be restored in Mivu on iPhone or Android; nothing calls it a backup or a sync.

## Screenshots

`docs/verification/android-widgets/` (synthetic diaries only):
- `backup-export-light.png`, `backup-export-dark.png`, `backup-export-font2.png` — compared with the mockup's
  "Backup & export: diary archive" frame: same group order, rows and copy; the mockup's leading square icons are
  circular tonal icons, as on Settings.
- `export-picker-light.png`, `export-picker-dark.png`, `export-picker-font2.png` — the system Create document picker
  with "Mivu-private-diary.json"; `export-saved-light.png` after saving.
- `restore-dialog-light.png` (replace, "My diary (0 meals)"), `restore-dialog-dark.png` (separate import,
  "Synthetic Profile (4 meals)"), `restore-dialog-font2.png` (replace, 4 meals); `reading-archive-dark.png` and
  `reading-archive-font2.png` show the "Reading archive" progress row.
- From earlier tasks of this milestone (same emulator): `widgets-light.png`, `widgets-font2.png`, `share-sheet.png`,
  `reply-notification.png`. Not taken in this task: `widget-no-target`, `launcher-shortcuts`, `qs-tile`,
  `share-chooser`, and dark/font-2.0 variants of the widget, share and notification shots.

## Limits

- Real-phone delivery of the reply notification and widget updates: `blocked` (no physical phone; emulator results do
  not prove notifications). Carried.
- Reading a 17 KB archive took about 4–8 s on the loaded emulator (debug build) before the dialog showed; not
  investigated.
- Export peak is about 100 MB of Java heap at 120 MB of photos (kotlinx encodes each photo as one base64 string).
  Carried to Play readiness.
- The notification small icon is still the generic placeholder, and the manifest has no launcher icon. Carried to
  Play readiness.
