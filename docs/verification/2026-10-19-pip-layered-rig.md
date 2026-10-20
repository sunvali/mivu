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
| **DiaryUITests/testMealPhotoViewerClosingAndCancelledDeletionPreserveRecord** | **fail (3 of 3 runs, incl. 2 isolated)** | **pass (full-class run and isolated)** |

Eight of the 12 failures also fail on baseline with identical messages (list-reachability, "Invalid frame dimension" warnings), so they are not caused by this branch. `testMealPhotoViewerClosingAndCancelledDeletionPreserveRecord` is a **non-baseline failure**: `reveal` cannot make `viewMealPhoto` reachable ("The target must be reachable; morning weight must clear fixed controls", `DiaryUITests.swift:88`). Cause not investigated; it is unresolved and must not be counted as passing. Baseline reachability failures in the same file suggest layout sensitivity on this simulator, but that is unconfirmed.

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
- Non-baseline UI failure above is unresolved.
- Reduce Motion in dark appearance, VoiceOver and Dynamic Type recordings were not made; Dynamic Type and accessibility coverage is only what the UI suite asserts.
- Hosted CI, signing and packaging: not part of this record.
