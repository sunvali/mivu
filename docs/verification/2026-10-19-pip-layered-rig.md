# Layered Pip rig: native acceptance record

- Tested source: `e2e92b17a8f9b15a03b96ca69f5ee034797bf7f0` (branch `feature/pip-layered-rig`), clean working tree.
- Environment: Xcode 27.0 (27A266a), iPhone 18 Pro simulator `80F2225B-C146-4E59-875C-35249B40F095`, iOS 27.0, macOS Darwin 27.0.0. Run through `xcodebuildmcp simulator test` with `-parallel-testing-enabled NO`.
- Result bundles live under `~/Library/Developer/XcodeBuildMCP/workspaces/mivu-coach-work-cab7b30193d5/result-bundles/` (not committed).
- Baseline for comparison: `5af19d4` (checked out in a temporary worktree, removed afterwards).

## Results

| Suite | Result | Bundle |
|---|---|---|
| `MivuTests` (856 discovered) | 855 passed, 0 failed, 1 skipped | `test_sim_2026-10-20T00-36-46-882Z_pid95372_40022eb2.xcresult` |
| `MivuUITests` (57 discovered) | 57 passed, 12 failed, 0 skipped (tool summary; counts include per-appearance repeats) | `test_sim_2026-10-20T00-38-57-530Z_pid95532_db118b81.xcresult` |
| `rig/test_rig.py` (`.venv/bin/python`) | 17 ran, OK | n/a |
| `python3 -m unittest discover -s scripts/ci -p 'test_*.py'` (the CI command) | 31 ran, OK | n/a |

Unit skip: `BrowserCallbackProbeTests/nativeAuthenticationBrowserReachesLoopback` (requires a real browser; not counted as passing). No known unit flake failed in this run.

### MivuUITests failures and baseline comparison

Baseline `5af19d4` was re-run for `CoachNavigationUITests`, `CoachUITests`, `DiaryUITests`, `ProgressUITests` (29 tests: 21 passed, 8 failed; bundle `test_sim_2026-10-20T01-36-35-842Z_pid2478_01308397.xcresult`).

| Test | HEAD | Baseline 5af19d4 |
|---|---|---|
| CompanionUITests/testFallbackKeepsCaptureAndReviewUsable | fail | known pre-existing |
| CompanionUITests/testLargestTextCameraCancelKeepsDraftAndSeparateLibraryReachable | fail | known pre-existing |
| CompanionUITests/testRapidTabsAndDetailReturnDoNotReplaySavedFeedback | fail | known pre-existing |
| CoachNavigationUITests/testDiaryDayAndBackdatedMealUseSameCoachAndHonestNoChat | fail | fail |
| CoachUITests/testLatestActivityAndReplyNeverAdvertiseAnUnreadMessage | fail | fail |
| CoachUITests/testRestingFingerDuringThinkingDoesNotDisableFollowing | fail | fail |
| CoachUITests/testThinkingFollowsLatestThenReplyPreservesHistoryAndJumpResumesFollowing | fail | fail |
| DiaryUITests/testCapturePhotoReviewCorrectionEditingAndHistory | fail | fail |
| DiaryUITests/testLogMealFromSelectedHistoricalDayKeepsTodaySeparate | fail | fail |
| ProgressUITests/testSavedGoalsWeightWorkoutAndReportsSurviveRelaunch | fail | fail |
| ProgressUITests/testSavedWorkoutSetsAndNoGoalReport | fail | fail |
| DiaryUITests/testMealPhotoViewerClosingAndCancelledDeletionPreserveRecord | pass after fix (3 of 3 class runs) | pass |

Eight of the 12 failures above also fail on baseline with identical messages (list-reachability, "Invalid frame dimension" warnings), so they are not caused by this branch.

### Meal photo regression: fixed

`testMealPhotoViewerClosingAndCancelledDeletionPreserveRecord` failed because the Today hero grew by 14 pt (the Pip frame is now derived from the rig crop at size 200, previously a fixed 186 pt tall frame). That moved the first meal row from y=684 to y=698, so its centre sat under the floating Log meal bar and the test's `row.tap()` opened the composer instead of the meal (probe: baseline row y=684, detail opened; HEAD row y=698, composer opened). Fix: Today Pip size 186 in `TodayView.companionArt`, restoring the old hero height. See `.superpowers/sdd/2026-10-19-pip-layered-rig/regression-meal-photo-report.md`.

Re-verification on source `464a3a8724025f79c7707fbe9889a02a9a7f2207` plus the fix (commit following it), same environment, `-parallel-testing-enabled NO`:

| Run | Result |
|---|---|
| `DiaryUITests` x3 (11 discovered each) | 9 passed, 2 failed each run; the 2 are baseline-identical (`testCapturePhotoReviewCorrectionEditingAndHistory`, `testLogMealFromSelectedHistoricalDayKeepsTodaySeparate`); the meal photo test passed in all 3 |
| `MivuUITests` full (57 discovered) | 57 passed, 12 failed (tool summary, counts include repeats): the 11 baseline-identical ones plus `CoachScrollSpikeUITests/testSpikeBidirectionalEvictionAndBackgroundReplyPreserveReader` (see below) |
| `MivuTests` full (856 discovered) | 855 passed, 0 failed, 1 skipped (same skip as above) |
| `CompanionUITests` Today and Coach tap/long-press | 2 passed |

Open: `testSpikeBidirectionalEvictionAndBackgroundReplyPreserveReader` passed in the earlier full run (e2e92b1) but failed here, in the full run and in two isolated runs (one with the fix stashed, so it is not caused by the fix; commits since e2e92b1 are docs only). Cause not investigated; not counted as passing.

## Evidence

Existing, under `docs/verification/pip-layered-rig/`: `head-spike/` (compare and spike stills, `spike.mp4`), `body/` (seated, standing, curled), `gestures/` (`all-gestures.mp4`, `blink-lid.mp4`), `idle/idle.mp4` (idle to curl-up), `runtime/` (Today and Coach stills, light and dark), `moments/moments.mp4` (first-meal hearts, tap escalation, head pat).

New recordings in `docs/verification/pip-layered-rig/acceptance/`, iPhone 18 Pro, synthetic input only ("two eggs and toast", "one apple"), launched with `--proof-light`/`--proof-dark`:

| Clip | Shows |
|---|---|
| `greet-light.mp4`, `greet-dark.mp4` | launch on Coach with Pip at rest (fixture mode) |
| `coach-light.mp4`, `coach-dark.mp4` | tap field, typing, submit, saved reply (`--coach-inference-fixture`) |
| `error-light.mp4`, `error-dark.mp4` | submit without an authorized connection: input saved, Pip says "Your input is safe here", Retry shown |
| `reduce-light.mp4` | same flow as `coach-light` with Reduce Motion set via `simctl spawn defaults write com.apple.Accessibility ReduceMotionEnabled` |

Limits: recordings were driven by manual taps, so typing-gaze and thinking phases are visible only as far as the clip shows them; they are review aids, not automated assertions. The Reduce Motion clip does not prove the setting took effect in the app (it was written to the simulator defaults and the app relaunched; policy is covered by `MotionPolicyTests` in the unit run). Dark `reduce` clip not recorded. Clips were re-encoded with `avconvert` (each under 1.7 MB).

## Blocked / not verified

- Physical iPhone performance: device "Yaakov’s IPhone" was offline. Instruments Animation Hitches (target under 5 ms/s) and idle CPU/energy were **not run**.
- `CoachScrollSpikeUITests` failure above is unresolved.
- Reduce Motion in dark appearance, VoiceOver and Dynamic Type recordings were not made; Dynamic Type and accessibility coverage is only what the UI suite asserts.
- Hosted CI, signing and packaging: not part of this record.
