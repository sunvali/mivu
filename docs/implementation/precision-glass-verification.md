# Precision Glass verification

## Source and environment

Final production and focused UI source: `21ca8c099e7c00f5c4e338a9db58939d8c44feab`.
Production `ios/Mivu` tree: `a6c05104dd7464197b223a0e0b0526fb1fbc3fcd`.

Local runs on 2026-10-16 UTC: macOS 27.0.1 arm64, Xcode 27.0 (27A266),
XcodeBuildMCP CLI 2.6.2, Debug Mivu scheme, parallel testing disabled.
Primary device: iPhone 18 Pro / iOS 27.0
(`80F2225B-C146-4E59-875C-35249B40F095`). Compatibility: iPhone 17 Pro /
iOS 26.5 (`42CE2315-9339-4EF1-A5B4-064444D0FA44`).

## Results

- Full unit suite on `a3bf7e5`: **436 passed, 0 failed, 1 skipped**.
  The additional history-window unit suite passes on final source; the push hook
  repeats the complete native unit suite for the final native tree.
  The skipped test requires an interactive authorization browser.
- **26 unique UI scenarios have passing latest outcomes** across the full scheme
  and focused reruns below. This is cumulative regression evidence, not one
  all-green final full-suite run. Earlier failures remain visible in the table.
- iOS 26.5: navigation/settings return and all six light/dark reference screens:
  **2 passed, 0 failed**. That run emitted one SwiftUI invalid-frame warning;
  no failed assertion or visible frame defect was observed in reference captures.
- Final iOS 26.5 largest-text restored-reply regression also passes on `7c2ef20` before the final history-reading guard.
- Independent source review through `21ca8c0` found no remaining material
  blockers in ownership, exact-ID edits, atomic moves, save/discard or Coach layout.

The original full run discovered stale native accessibility assumptions and layout
defects: restored Coach replies could lie outside the actual viewport, and chart
domain endpoints could exclude dated samples. Later runs cover their fixes.
Progress disclosure and weight-row tests bring controls fully into view before
tapping. Screen recordings and accessibility trees then reproduced visible older
Coach rows missing from the native accessibility hierarchy after restoration.
Explicitly laid-out history pages fix both old-message and latest-reply access.
The initial page contains the latest 20 turns; Show earlier messages expands it
backward. A stable starting UUID prevents new arrivals from evicting history being
read. Loaded pages and new arrivals can grow the current session; reopening resets
to the latest page. Paging, append, profile reset and missing-anchor recovery are
covered by focused units and a native paging/unread-message UI journey.
A geometry update cannot override explicit history-reading intent unless the user
actually returns to the bottom or requests following. Profile reset no longer
overwrites measured geometry, and unread navigation derives from reading intent.
This resolves a reproduced stale-distance flag that hid New message after paging. Exact text,
hittability and restored-reply positioning assertions remain enforced.

| Run | Source | Passed / failed / skipped | Result bundle |
|---|---|---|---|
| final | `4f53fd4fe1c10e5eb8f826cf454385c56df5d3ca` | 454 / 6 / 1 | `/private/tmp/mivu-precision-final.xcresult` |
| regression | `16bd53648df43657d89b7fa012fb9159b83e7b6e` | 445 / 4 / 1 | `/private/tmp/mivu-precision-regression.xcresult` |
| anchor | `664bb3a0c2a6d06d3b07d462b6de71cea6df057f` | 1 / 1 / 0 | `/private/tmp/mivu-precision-anchor.xcresult` |
| restore | `a3bf7e59f2cba2442d86aa5ec2e5b52a0f3337f0` | 443 / 1 / 1 | `/private/tmp/mivu-precision-restore.xcresult` |
| ios26 | `a3bf7e59f2cba2442d86aa5ec2e5b52a0f3337f0` + failure-only test diagnostics | 2 / 0 / 0 | `/private/tmp/mivu-precision-ios26.xcresult` |
| coachfinal | `7c2ef208e012a5081c0904baefa95c1c7194a8cc` | 14 / 1 / 0 | `/private/tmp/mivu-precision-coachfinal.xcresult` |
| compatfinal | `7c2ef208e012a5081c0904baefa95c1c7194a8cc` | 1 / 0 / 0 | `/private/tmp/mivu-precision-compatfinal.xcresult` |
| pagingfinal | `6d8b496293151af92e9ac7644a14e80186c9b148` | 0 / 1 / 0 | `/private/tmp/mivu-precision-pagingfinal.xcresult` |
| readingfinal | `21ca8c099e7c00f5c4e338a9db58939d8c44feab` | 5 / 0 / 0 | `/private/tmp/mivu-precision-readingfinal.xcresult` |

## Latest UI scenario evidence

| Scenario | Latest passing run |
|---|---|
| `CoachActivityUITests/testReceiptOpensNativeBackupSettingsWithoutStartingFilesAction` | final |
| `CoachUITests/testEarlierMessagesRemainReadableWhenNewInputArrives` | readingfinal |
| `CoachUITests/testFixtureGoalsWeightWorkoutBudgetAndRelaunch` | coachfinal |
| `CoachUITests/testFixtureMealCorrectionHistoricalReviewAndConversationRelaunch` | coachfinal |
| `CoachUITests/testLargestDynamicTypeDarkCoachKeepsCaptureReachable` | coachfinal |
| `CoachUITests/testLatestActivityAndReplyNeverAdvertiseAnUnreadMessage` | readingfinal |
| `CoachUITests/testLatestFollowsActionsAndHistoryOffersNewMessage` | readingfinal |
| `CoachUITests/testOfflineTextPhotoCapturePersistsAcrossRelaunchAndTabs` | coachfinal |
| `CoachUITests/testRestingFingerDuringThinkingDoesNotDisableFollowing` | readingfinal |
| `CoachUITests/testThinkingFollowsLatestThenReplyPreservesHistoryAndJumpResumesFollowing` | readingfinal |
| `DiaryUITests/testCancelDoesNotCreateMealAndProfilesRemainSeparate` | final |
| `DiaryUITests/testCapturePhotoReviewCorrectionEditingAndHistory` | regression |
| `DiaryUITests/testEnglishDarkLargeTextRendering` | final |
| `DiaryUITests/testFirstRunCreatesNamedDiaryWithoutInventingRecords` | final |
| `DiaryUITests/testLegacyHebrewLaunchUsesEnglishLeftToRight` | regression |
| `DiaryUITests/testLogMealFromSelectedHistoricalDayKeepsTodaySeparate` | final |
| `DiaryUITests/testMealPhotoViewerClosingAndCancelledDeletionPreserveRecord` | final |
| `DiaryUITests/testPhotoOnlyReviewHasReadableMealTitle` | final |
| `DiaryUITests/testPrecisionGlassNavigationAndSettingsReturn` | ios26 |
| `DiaryUITests/testPrecisionGlassReferenceScreensInBothAppearances` | coachfinal |
| `DiaryUITests/testUnsavedSettingsRequireExplicitDiscard` | final |
| `ProgressUITests/testFilledGoalLabelsAndClearingLastTargetSurviveRelaunch` | final |
| `ProgressUITests/testLargestTextDarkProgressKeepsReportsAccessible` | anchor |
| `ProgressUITests/testSavedGoalsWeightWorkoutAndReportsSurviveRelaunch` | final |
| `ProgressUITests/testSavedWorkoutSetsAndNoGoalReport` | regression |
| `ProgressUITests/testWeightChartSelectsSavedMeasurement` | final |

## Reproduction and artifact locations

All native runs used XcodeBuildMCP `simulator test` with JSON arguments specifying
project `/private/tmp/mivu-local-hooks/ios/Mivu.xcodeproj`, scheme `Mivu`, Debug,
`preferXcodebuild: true`, the device UUID above, derived data
`/private/tmp/mivu-precision-derived`, and `-parallel-testing-enabled NO`.
Exact selection arguments are in `/private/tmp/mivu-precision-<run>-args.json`;
parsed results retain request, selected tests, counts and log/result paths.
The local wrapper `/private/tmp/mivu-run-verification.py <run>` invokes the CLI
with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` and propagates its
exit status. Each run uses a fresh result-bundle path.

Durable local review artifacts are in the task workspace under
`output/precision-glass-implementation/2026-10-16/`: twelve final light/dark PNGs,
PDF generation source, source manifest and `verification/` parsed run records,
per-scenario outcomes and provenance. PDF:
`output/pdf/Mivu-Precision-Glass-Implementation.pdf`.
Screens were captured at production source `7c2ef20`, before the history-reading guard, using synthetic sample data.
The PDF covers Today, capture, Diary, Progress, Coach and Settings.

## Acceptance boundaries

Simulator checks do not prove physical camera/library permissions, hardware
VoiceOver or haptics, live provider authorization/inference, remote Files-provider
upload, or phone installation. These remain unverified. No release, distribution,
merge, new provider, schema migration or new dependency is included.
The saved-history screen uses only stored submission metadata; complete timestamped
before/after auditing and rollback are not added. The app icon has default, dark
and tinted assets; no layered Icon Composer project is included.

Push-hook unit and script evidence, and hosted script/title check URLs, are recorded
in the pull request after the final documentation commit. They do not replace the
native UI results above.
