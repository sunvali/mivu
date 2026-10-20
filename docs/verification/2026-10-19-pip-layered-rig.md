# Layered Pip rig: native acceptance record

- Tested source: `2ee9faa157516d2c6e6715d08241c1ddd94b60a5` (branch `feature/pip-layered-rig`), clean working tree. Later commits on the branch change docs only.
- Environment: Xcode 27.0 (27A266a), iPhone 18 Pro simulator `80F2225B-C146-4E59-875C-35249B40F095`, iOS 27.0, macOS Darwin 27.0.0. Run through `xcodebuildmcp simulator test` with `-parallel-testing-enabled NO`.
- Result bundles live under `~/Library/Developer/XcodeBuildMCP/workspaces/mivu-coach-work-cab7b30193d5/result-bundles/` (not committed).
- Baseline for comparison: the true merge base `5a63421`, checked out in a temporary worktree with its own derived data (removed afterwards).

## Results

| Suite | Result | Bundle |
|---|---|---|
| `MivuTests` | 866 passed, 0 failed, 1 skipped | `test_sim_2026-10-20T04-29-23-119Z_pid23205_6edfab6d.xcresult` |
| `MivuUITests` | 69 executed: 58 passed, 11 failed, 0 skipped | `test_sim_2026-10-20T04-31-50-756Z_pid23452_682ae17e.xcresult` |
| `rig/test_rig.py` (`.venv/bin/python`) | 17 ran, OK | n/a |
| `python3 -m unittest discover -s scripts/ci -p 'test_*.py'` | 31 ran, OK | n/a |

Unit skip: `BrowserCallbackProbeTests/nativeAuthenticationBrowserReachesLoopback` (needs a real browser; not counted as passing).

### MivuUITests failures and true-base comparison

Base `5a63421` was run for the four tests that were previously only compared against the mid-branch commit `5af19d4`: the three CompanionUITests below (3 executed, 0 passed, bundle `test_sim_2026-10-20T04-17-15-759Z_pid20465_b1406756.xcresult`) and the Coach spike (1 executed, 0 passed, bundle `test_sim_2026-10-20T04-24-30-974Z_pid22393_1ecae615.xcresult`). The 8 other failures live in code this branch does not touch (Coach, Diary, Progress) and also failed on `5af19d4` with identical messages.

| Test | HEAD `2ee9faa` | Base `5a63421` | Verdict |
|---|---|---|---|
| CompanionUITests/testFallbackKeepsCaptureAndReviewUsable | fail (`coachMealLink` "Needs review" button not found) | fail (`XCTAssertTrue`) | pre-existing |
| CompanionUITests/testLargestTextCameraCancelKeepsDraftAndSeparateLibraryReachable | fail (targets 20.3 and 43.0 pt, under 44) | fail (same two values) | pre-existing |
| CompanionUITests/testRapidTabsAndDetailReturnDoNotReplaySavedFeedback | fail (`XCTAssertFalse`, CompanionUITests.swift:291) | fail (`XCTAssertFalse`) | pre-existing; the no-replay rule is covered by `CompanionPresentationTests` and `CompanionRootIntegrationTests` in the unit run, but this UI guard cannot be counted as passing |
| CoachScrollSpikeUITests/testSpikeBidirectionalEvictionAndBackgroundReplyPreserveReader | pass in this run | fail (`fixtureFacts` XCTUnwrap, `waitForReply` timeout) | environmental flake: fails on the base and earlier on this branch, passed here; not a branch regression |
| CoachNavigationUITests/testDiaryDayAndBackdatedMealUseSameCoachAndHonestNoChat | fail | fail on 5af19d4 | pre-existing |
| CoachUITests/testLatestActivityAndReplyNeverAdvertiseAnUnreadMessage | fail | fail on 5af19d4 | pre-existing |
| CoachUITests/testRestingFingerDuringThinkingDoesNotDisableFollowing | fail | fail on 5af19d4 | pre-existing |
| CoachUITests/testThinkingFollowsLatestThenReplyPreservesHistoryAndJumpResumesFollowing | fail | fail on 5af19d4 | pre-existing |
| DiaryUITests/testCapturePhotoReviewCorrectionEditingAndHistory | fail | fail on 5af19d4 | pre-existing |
| DiaryUITests/testLogMealFromSelectedHistoricalDayKeepsTodaySeparate | fail | fail on 5af19d4 | pre-existing |
| ProgressUITests/testSavedGoalsWeightWorkoutAndReportsSurviveRelaunch | fail | fail on 5af19d4 | pre-existing |
| ProgressUITests/testSavedWorkoutSetsAndNoGoalReport | fail | fail on 5af19d4 | pre-existing |

No test passes on `5a63421` and fails on HEAD among the four re-run on the true base. The 8 Coach, Diary and Progress failures were compared only with `5af19d4` (not re-run on the base); they sit in files this branch does not change.

### Meal photo regression: fixed earlier

`testMealPhotoViewerClosingAndCancelledDeletionPreserveRecord` failed because the Today hero grew by 14 pt; the Today Pip size is now 186 in `TodayView.companionArt`, restoring the old hero height. It passes in the run above.

### Final-review fixes covered by focused unit tests

`CompanionRigRuntimeTests`, `PipRigViewTests`, `PipIdleSchedulerTests`, `DiaryCompanionMomentTests`, `PipGestureTests`, `CompanionMountTests`, `CompanionRootIntegrationTests`, `CompanionPresentationTests`: 110 passed (bundle `test_sim_2026-10-20T04-27-43-501Z_pid22727_ade92e7e.xcresult`). Each new test failed first against the pre-fix product code (typing update, reaction lifetimes, static poses, stale and cross-surface idle beats, hug-then-curl on Coach, `wake` end set, three playback-leak probes).

## Evidence

Existing, under `docs/verification/pip-layered-rig/`: `head-spike/` (compare and spike stills, `spike.mp4`), `body/` (seated, standing, curled), `gestures/` (`all-gestures.mp4`, `blink-lid.mp4`), `idle/idle.mp4` (idle to curl-up), `runtime/` (Today and Coach stills, light and dark), `moments/moments.mp4` (first-meal hearts, tap escalation, head pat).

New recordings in `docs/verification/pip-layered-rig/acceptance/`, iPhone 18 Pro, synthetic input only ("two eggs and toast", "one apple"), launched with `--proof-light`/`--proof-dark`:

| Clip | Shows |
|---|---|
| `greet-light.mp4`, `greet-dark.mp4` | launch on Coach with Pip at rest (fixture mode) |
| `coach-light.mp4`, `coach-dark.mp4` | tap field, typing, submit, saved reply (`--coach-inference-fixture`) |
| `error-light.mp4`, `error-dark.mp4` | submit without an authorized connection: input saved, Pip says "Your input is safe here", Retry shown |
| `reduce-light.mp4` | same flow as `coach-light` with Reduce Motion set via `simctl spawn defaults write com.apple.Accessibility ReduceMotionEnabled` |

Limits: recordings were driven by manual taps, so typing-gaze and thinking phases are visible only as far as the clip shows them; they are review aids, not automated assertions. The Reduce Motion clip does not prove the setting took effect in the app (it was written to the simulator defaults and the app relaunched; policy is covered by `MotionPolicyTests` in the unit run). Dark `reduce` clip not recorded. Clips were re-encoded with `avconvert` (each under 1.7 MB); `idle/idle.mp4` is trimmed to its first 15 s (0.7 MB).

## Blocked / not verified

- Physical iPhone performance: device "Yaakov’s IPhone" was offline. Instruments Animation Hitches (target under 5 ms/s) and idle CPU/energy were **not run**.
- `CoachScrollSpikeUITests` failure above is pre-existing (reproduces on 5af19d4), not caused by this branch; still unresolved.
- Reduce Motion in dark appearance, VoiceOver and Dynamic Type recordings were not made; Dynamic Type and accessibility coverage is only what the UI suite asserts.
- Hosted CI, signing and packaging: not part of this record.
