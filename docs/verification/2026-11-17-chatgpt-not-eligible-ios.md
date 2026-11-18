# ChatGPT plan not eligible — iOS verification

- Spec: `docs/superpowers/specs/2026-11-17-chatgpt-free-tier-design.md`
- Plan: `docs/superpowers/plans/2026-11-17-chatgpt-free-tier-ios.md`
- Tested source: `3b6be37b` for the focused and UI tests below; full unit suite at `d7bb3dac` (the later fix only adds an in-progress flag)
- Environment: Xcode 27.2, iPhone 17 Pro simulator "Mivu free-tier" (iOS 27.0), XcodeBuildMCP, Debug, serial

## Focused tests

| Suite | Result |
| --- | --- |
| `MivuTests/ResponsesClientTests` + `ConnectionTests` + `CoachConnectionTests` (403 not-eligible, plain 403, stream error, state, persistence, on-device fallback, sign-in check, welcome waits for the check, transient failures, second consent, disconnect, re-check on open, throttle) | 94 passed |
| `MivuTests/CoachEngineTests/permissionFailuresKeepCapturedTurnWaiting` (incl. `.notEligible`) | passed |
| `MivuUITests/CoachUITests/testPlanNotEligibleExplainsOnceAndInSettings` | passed |
| `MivuUITests/CoachUITests/testOfflineTextPhotoCapturePersistsAcrossRelaunchAndTabs`, `MivuUITests/SmokeUITests` | passed |
| `MivuUITests/DiaryUITests/testSetupSkipsConnectForAPlanThatCannotBeUsed` + `testFirstRunOpensSetupWithoutInventingRecords` + `CoachUITests/testPlanNotEligibleExplainsOnceAndInSettings` (setup skips Connect for a plan OpenAI won't share) | 3 passed |
| `scripts/ci/languages.py check` | clean |

## Full unit suite

`MivuTests`: 1,448 passed, 18 failed, 1 skipped. Result bundle: `/Users/yaakovkhodorkovski/Library/Developer/XcodeBuildMCP/workspaces/mivu-free-tier-3bf596a12d45/result-bundles/test_sim_2026-11-17T20-21-26-026Z_pid61824_74159023.xcresult`.

The same 18 tests fail at the branch base `08b71c47` (main `dce655de` plus docs) on the
same simulator: date, day-boundary and progress tests in CoachEngine, CoachStore,
CoachReplyLines, CoachFocus, CoachBatchTransaction, CompanionRootIntegration,
DiaryProjectionMutation and DiaryReport. They are pre-existing and unrelated.

## Visual check

Alert, Coach bubble and Settings → Coach AI were inspected on the simulator with the
`--plan-not-eligible-fixture` launch argument. Hebrew strings are drafts for the owner's review.

## Blocked

- Live check with a real Free ChatGPT account: blocked, owner-only. It also answers whether
  a Free account is granted the plan scope at consent.
- Full UI suite: not run (targeted runs only).
