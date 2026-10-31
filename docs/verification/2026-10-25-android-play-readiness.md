# Android milestone 9: Play readiness

Plan: [android-play-readiness](../superpowers/plans/2026-10-25-android-play-readiness.md). Submission draft:
[play-submission.md](../development/play-submission.md). Nothing was entered in Play Console, no terms were accepted,
nothing was signed with an owner key, uploaded or published.

## Environment

- Host: macOS (Darwin 27.0.0), Android Studio JBR, Gradle 9.8.2, AGP 9.4.1, build-tools 36.0.0.
- Emulator: `Medium_Phone_API_37.0` (API 37, emulator 37.2.12.0), time zone Asia/Jerusalem.
- Date: Sunday 2026-10-25, 22:55–23:50 local. **This was the day Israel left daylight saving time (a 25-hour day)**,
  and a Sunday, which matters for the clock-sensitive tests below.

## Source

- Full suite: `8ff04d6efe1402a4724a83d2f90397d692303054` (clean tree;
  `fix(android): bound saved reports and offer sharing without a mail app`).
- Test fixes after the full run: `3608faebc2092857681c9a93425bd37bff0c5de9`; the release smoke, timings and screenshots
  ran at this commit.

## Commits in milestone 9

| Commit | What |
|---|---|
| `9923b505` | Upload signing from four `MIVU_UPLOAD_*` values, lint before Android pushes |
| `3965623f`, `1e3ad1ec` | Pip adaptive launcher icon with a themed layer; `ic_stat_pip` notification icon |
| `63b2bbe4`, `34dc49e1` | `ReleaseSmokeTest` on the R8-minified release build, always debug-signed |
| `8c0500d2`, `7fcb79e1` | Coach meal-chip icon, Choose photos clear of the shutter, two flaky-test fixes |
| `ae5ff0f6` | Report a Coach reply (email to support@mivuapp.com) |
| `8ff04d6e` | Saved reports bounded to the newest 200 lines / 256 KB through a temp file and atomic rename; torn lines skipped on read; "Share" beside "Copy address" when no mail app exists |
| `3608faeb` | Test fixes found by the full run (below) |

## Decisions (from the plan)

- Keep Android 12 (minSdk 31): API 31–32 is about 9.9 % of devices (apilevels.com, read 2026-10-25). Lint `NewApi`
  now blocks pushes.
- Target API 37 (Play requires 36 for new apps from 31 August 2026).
- Material 3 Expressive stays deferred (material3 1.4.0 is the newest stable; 1.5.0 is beta). Moved to Later.
- Backup rules already match "device transfer only, no cloud backup"; pinned by `BackupRulesTest`.
- Debug code is out of release; `releaseShipsNoDebugComponents` checks the installed release package.
- 16 KB pages: checked (below).
- Account deletion: not applicable, no Mivu account.
- Archive export memory (about 100 MB heap at 120 MB photos): moved to Later, trigger "a physical phone fails the
  120 MB export".
- Owner rulings 2026-10-25: AI-content reports in the app by email to support@mivuapp.com; the OpenAI transfer is
  declared **shared** in Data safety; the physical-phone checks are listed below for when the phone arrives.

## Full suite (`8ff04d6e`)

```sh
cd android
./gradlew :app:testDebugUnitTest :app:connectedDebugAndroidTest :app:lintDebug :app:assembleRelease --rerun-tasks --continue
```

BUILD FAILED in 21 min only because `connectedDebugAndroidTest` had failures; the other tasks ran.

| Task | Result |
|---|---|
| `testDebugUnitTest` | 44 classes, **337 passed**, 0 failed, 0 skipped |
| `connectedDebugAndroidTest` | 56 classes, 488 run: **482 passed, 6 failed**, 0 skipped |
| `lintDebug` | 0 errors, 37 warnings |
| `assembleRelease` | built, unsigned (`app-release-unsigned.apk`) |

Counts are from the JUnit XML (`app/build/test-results/testDebugUnitTest/*.xml`,
`app/build/outputs/androidTest-results/connected/debug/*.xml`), per test case. No class had zero tests.
`ReleaseSmokeTest` counts 6 on debug; `releaseShipsNoDebugComponents` returns early on debug by design.

Unit classes (passed): AuthSessionTest 19, BackupRulesTest 2, ChatGPTConnectionTest 17, CoachHistoryModelTest 4,
CoachHistoryWindowTest 7, CoachReceiptPresentationTest 4, CoachReplyCheckTest 2, CoachReplyNotificationTest 7,
CoachReplyTextTest 1, CoachReportsTest 1, CoachToolsTest 12, CoachVoiceInputTest 4, CompanionPresentationTest 18,
CompanionRuntimeTest 7, DayStatusTest 4, DiaryArchiveTest 8, DiaryMathTest 8, DiaryModelsTest 4, DiaryReportTest 5,
DiaryRestoreTest 8, DiaryValidationTest 21, DiaryViewModelTest 4, FoodEditTest 1, GoalEditorValuesTest 5,
IdTokenValidatorTest 8, LoopbackCallbackTest 5, ManualNutritionDraftTest 5, MivuThemeTest 2, MorningReminderTest 3,
MotionPolicyTest 6, OAuthAttemptTest 12, OnboardingTargetsTest 6, PipGestureLibraryTest 8, PipIdleSchedulerTest 5,
PipMotionTest 12, PipRigAssetTest 9, PipRigSceneTest 10, ProgressInsightsTest 32, ResponsesClientTest 12,
SampleAnalyzerTest 8, SwiftJsonTest 8, TodayViewModelTest 7, WakingDayInstructionTest 1, WidgetSnapshotTest 5.

Connected classes (passed / run): AppBackgroundTest 2/2, AppIconTest 2/2, AppShellTest 5/5, ArchiveRoundTripTest
12/12, BackupExportScreenTest 14/14, CaloriesWidgetTest 9/9, CoachCameraTest 7/7, CoachComposerTest 21/21,
CoachContextTest 9/9, CoachEngineTest 11/11, CoachHistoryScreenTest 11/11, CoachJobServiceTest 5/5,
CoachProgressWritesTest 4/4, CoachReadsTest 4/4, CoachReplyActionsTest 14/14, CoachReplyFollowTest 3/3,
**CoachScreenTest 18/19**, CoachSegmentsTest 14/14, CoachSummaryLinesTest 10/10, CoachTimelineTest 11/11,
CoachVoiceTest 6/6, CoachWorkerTest 11/11, CoachWritesTest 18/18, ConnectionProofScreenTest 2/2,
ConnectionScreenTest 12/12, CredentialStoreTest 7/7, DiaryCaptureTest 16/16, DiaryDatabaseTest 23/23, DiaryDaysTest
6/6, DiaryQueriesTest 4/4, DiaryReportPdfTest 2/2, DiaryScreenTest 9/9, EditorsTest 10/10, ManualNutritionScreenTest
6/6, ManualNutritionStoreTest 4/4, MealAnalysisTest 12/12, MealAnalysisWorkerTest 6/6, MealCaptureTest 2/2,
MealComposerScreenTest 9/9, MealDetailScreenTest 11/11, MealEditorsTest 7/7, MealEditsTest 10/10,
**MorningCheckInTest 12/13**, **MorningReminderReceiverTest 3/4**, OnboardingScreenTest 15/15, PipCompanionTest 3/3,
PlanWelcomeTest 2/2, ProgressQueriesTest 8/8, ProgressScreenTest 9/9, **QuickCaptureTest 8/9**, ReleaseSmokeTest 6/6,
ReviewedOriginTest 2/2, **ShareToCoachTest 9/10**, TellCoachTest 8/8, **TodayCompanionTest 4/5**, TodayScreenTest 14/14.

### Failures and causes

| Test | Cause | Outcome |
|---|---|---|
| `TodayCompanionTest.foregroundOnALaterDayWelcomesBack` | Test bug: it stepped back 86,400,000 ms for "yesterday". On the 25-hour DST day, 24 h before 23:2x is still the same date. | Fixed in `3608faeb` (steps back one calendar day). Failed alone before the fix, class 5/5 after. |
| `MorningReminderReceiverTest.disabledReceiverPostsNothing` | Test bug: `cancelAll()` is asynchronous, so the previous test's morning notification was still listed. Passed alone (4/4). | Fixed in `3608faeb` (reset waits until it is gone). Class 4/4 after. |
| `CoachScreenTest.dayChoiceLogsToChosenDay` | Known clock dependency (fails on a Sunday or before the cutoff), already carried. | Not changed; stays carried. |
| `QuickCaptureTest.snapItWhileOpenReusesTheActivity` | Environment: 57 s, `ActivityScenario` never reached DESTROYED on the loaded emulator. | Class 9/9 when run alone. Not counted as a pass in the full run. |
| `ShareToCoachTest.deniedPermissionPostsNothingAndSaves`, `MorningCheckInTest.deniedNotificationPermissionExplainsTheOffSwitch` | Assumption stops ("permission already granted on this install"); connected runs report a JUnit assumption as a failure. | Not counted as passes. They need a fresh install without the notification grant. |

## Release smoke (`3608faeb`)

```sh
./gradlew :app:connectedReleaseAndroidTest -Pmivu.testBuildType=release \
  -Pandroid.testInstrumentationRunnerArguments.class=com.yakov103.mivu.release.ReleaseSmokeTest
```

`ReleaseSmokeTest` on the minified, debug-signed release build: **6 passed**, 0 failed, 0 skipped
(`mainActivityStarts` 14.9 s, `widgetDrawsUnderR8`, `shareSheetOpens` 7.0 s, `archiveReadTime`,
`androidAndIosFixturesDecode`, `releaseShipsNoDebugComponents`).

**Archive read** (`ios-v4-full.json`, 17 KB, five decodes through a PhotoSpool; `am instrument`, method alone, three
runs each):

| Build | `archiveFirstReadMs` | `archiveReadMs` (median) |
|---|---|---|
| release | 6, 5, 6 | 4, 2, 3 |
| debug | 38, 35, 34 | 21, 19, 20 |

The release read is far under 1 s. The 4–8 s seen when restoring in milestone 8 is therefore elsewhere in the restore
flow (picker, `openInputStream`, the restore transaction); carried with "trace before changing it".

**16 KB pages:** `zipalign -c -P 16 4 app-release.apk` (build-tools 36.0.0): verification succeeded. Native libraries
(each for arm64-v8a, armeabi-v7a, x86, x86_64): `libandroidx.graphics.path.so`, `libimage_processing_util_jni.so`,
`libsurface_util_jni.so`.

## Scripts (`8ff04d6e`)

- `python3 scripts/ci/parity.py`: passed (run again after this record's parity edits).
- `python3 scripts/ci/play_ledger.py android/play-uploads.txt`: exit 0 (header only; no upload yet).
- `python3 -m unittest discover -s scripts/ci -p 'test_*.py' < /dev/null`: **53 passed**.

## Report fixes (`8ff04d6e`)

- `CoachReportsTest.keepsTheNewestLinesAndSkipsATornOne` (unit): a torn first line plus 205 reports keeps the newest
  200 in order with no temp file left; 100 reports with 4 KB notes stay under 256 KB and end with the newest.
- `CoachReplyActionsTest.noEmailAppOffersAShareSheetWithTheSameReport` (connected): with no mail app, "Share" opens one
  `ACTION_CHOOSER` wrapping `ACTION_SEND` with the address and the same body; the report stays saved.
- `CoachReplyActionsTest` 14/14 and `CoachReportsTest` 1/1 before the commit and in the full run.

## Screenshots

Emulator at 1080 × 1920 (`wm size`, 9:16 for Play), demo-mode status bar (9:41), synthetic data from
`TodayFixtureSeed` (`seedCoach timeline` / `empty`), debug build. In
[`android-play/`](android-play/):

| File | What | Compared with |
|---|---|---|
| `play-01-today.png` | Today with Pip, 1,525 of 2,000 kcal | iOS `02-today.png`: same card order and figure |
| `play-02-coach.png` | Coach timeline: question with the meal chip (now with its icon), Pip, composer | iOS `01-coach.png`; shows the "Connect ChatGPT" notice because the emulator is not connected |
| `play-03-progress.png` | Progress, week chart with Pip presenting | iOS `03-progress.png`; the seed has no weights, so the chart is the empty "Let's get started" state |
| `play-04-diary.png` | Diary week strip, day card, meals | iOS `05-diary.png` |
| `play-05-widget.png` | Small calories widget on the home screen | iOS widget: figure, goal bar, Pip |
| `widget-no-target.png`, `-dark`, `-font2` | Widget with no goal: "0 kcal recorded", "Set a target" | iOS small widget without a target. At font scale 2.0 Pip sits under the end of "Set a target" and "kcal recorded"; the text draws on top and stays readable (carried as polish). |
| `launcher-shortcuts.png`, `-font2` | Long-press on Mivu: Widgets, Snap It, Coach | iOS quick actions |
| `qs-tile.png` | Snap It tile (camera) at the top of Quick Settings | Control Center control on iOS |
| `share-chooser.png` | System share sheet for text listing Mivu | iOS share extension |
| `launcher-icon*.png`, `notification-icon.png` | From Task 2 | iOS `AppIcon` |

The Play listing screenshots are raw captures; framing and captions are the owner's choice. The medium widget was not
captured (the launcher's resize handle did not take a scripted drag).

## Physical phone (owner)

Every item is **blocked** until run on a real Android 12+ phone (an Android 12 or 12L phone also covers the
clipboard item). Install the release build the way Play will deliver it:

1. Set the four `MIVU_UPLOAD_*` values, run `./gradlew :app:bundleRelease`, then
   `bundletool build-apks --bundle=app/build/outputs/bundle/release/app-release.aab --output=mivu.apks --connected-device`
   and `bundletool install-apks --apks=mivu.apks`. Record the phone model, Android version and the source SHA.

| # | Check | Steps | Pass when | Result |
|---|---|---|---|---|
| P1 | Phase 0 item 2: sign-in | Settings › Coach AI › Connect ChatGPT › Agree and Continue; sign in in the Custom Tab; after "You can return to Mivu" press Back. Then force-stop Mivu and sign in again. | Settings shows Connected both times; no crash | blocked |
| P2 | Phase 0 item 3: inference | In Coach send "two boiled eggs and a slice of toast". Leave the app mid-reply, come back. | Pip replies and a meal with nutrition is saved; leaving mid-turn still finishes it | blocked |
| P3 | Phase 0 item 4: photo analysis | In Coach take a photo of a drawn or printed test plate (not personal food) and send it. | A meal with an estimate is saved from the photo | blocked |
| P4 | Phase 0 item 5: refresh and Disconnect | Leave the phone signed in past the token expiry (or use the debug proof screen's Force refresh on a debug install), then send a message. Then Settings › Disconnect ChatGPT and send another message. | The first message is answered without signing in again; after Disconnect the new message saves as waiting for a connection | blocked |
| P5 | Pip smoothness | Open Today and Coach, tap and pat Pip, watch idle for a minute. Optionally `adb shell dumpsys gfxinfo com.yakov103.mivu`. | No visible stutter; janky frames low | blocked |
| P6 | TalkBack | Turn on TalkBack; move through Today, Diary, Progress, Coach and Settings; long-press a Pip reply via the actions menu (Reply, Copy, Report reply). | Every control is announced with a label; actions reachable | blocked |
| P7 | Live voice | In Coach tap the mic, say "a banana and a coffee", stop. | The words appear in the composer for review before sending | blocked |
| P8 | Keyboard on non-Coach screens | Open Add manually, a food editor, the goal editor and Add weight; focus each text field. | The focused field stays visible above the keyboard (`adjustPan`) and nothing is hidden behind it | blocked |
| P9 | Composer gap | In Coach focus the composer with the keyboard open, then closed. | No gap between the composer and the keyboard or the navigation bar | blocked |
| P10 | Widget | Add the Mivu widget; log a meal; wait past 04:00 the next morning. | The widget updates after the capture and resets after the cutoff; Snap It and Coach open the right screens | blocked |
| P11 | Notifications | Share a text into Mivu and leave it; turn on the morning reminder for a minute ahead. | The Coach reply notification and the morning notification arrive with the Pip small icon, and a tap opens Coach / Today | blocked |
| P12 | API 31–32 clipboard toast | On Android 12/12L, long-press a reply › Copy. | A "Copied" toast appears once (Android 13+ shows the system clipboard preview instead), and the text pastes | blocked |
| P13 | Restore time | Export the diary to Drive and to Downloads; Backup & export › Restore from diary archive from each. Time from picking the file to the confirmation. | Note the seconds for each; under about 2 s is fine, 4–8 s means the restore-flow trace is needed | blocked |
| P14 | Report a reply | Long-press a Pip reply › Report reply › reason › Report, with an email app installed. | The email draft opens to support@mivuapp.com with the reply text | blocked |

Device-to-device restore (two phones) is optional.

## Owner checklist

Nothing here is an agent task.

1. Ask Play support whether a nutrition tracker needs an organization (D-U-N-S) or a personal account.
2. Create the Play Console account, pay the fee, verify identity, accept the Developer Distribution Agreement.
3. Create the upload keystore outside the repo, set the four `MIVU_UPLOAD_*` values, enroll in Play App Signing.
4. Get OpenAI's written answer on ChatGPT sign-in for a closed-source Play app (Phase 0 item 1).
5. Authorize and create the reviewer ChatGPT account (Phase 0 item 6); enter it under App access.
6. Publish `https://mivuapp.com/privacy` and the support page; enter the URL.
7. Create the `support@mivuapp.com` mailbox before release.
8. Fill in the Console forms from [play-submission.md](../development/play-submission.md), checking every "owner to
   confirm" answer against the live form.
9. Run the "Physical phone" checks above.
10. Build, sign and upload the first AAB; add and commit the ledger line; read the pre-launch report.
11. Run the closed test: 12 testers opted in for 14 continuous days, then decide on production.
