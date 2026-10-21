# Pip entry points — verification

- **Source:** `feat/pip-entry-points`; feature code at `d5c147a`, review fixes at `2f92a23`, test fix at `30f0de7`, Diary toolbar change in the commit after `30f0de7`.
- **Environment:** Xcode 27.0 (27A266a), macOS 27.0.1, iPhone 17 Pro simulator `42CE2315-9339-4EF1-A5B4-064444D0FA44`; device install on iPhone 15 Pro `00008130-00112DD436A0001C` (iOS 27.0.1). XcodeBuildMCP was not available as a tool in this session, so `xcodebuild` ran directly.
- **Spec / plan:** `docs/superpowers/specs/2026-10-21-pip-entry-points-design.md`, `docs/superpowers/plans/2026-10-21-pip-entry-points.md`
- **Test scope (owner policy):** only the tests this branch adds or edits, once each; no full UI suite.

## Automated

| Run | Revision | Result |
|---|---|---|
| `MivuTests/CoachReplyTests` + `CoachReplyContextTests` | `d5c147a` | 12 tests in 2 suites passed |
| 17 UI tests the branch added or edited | `d5c147a` | 12 passed, 5 failed (below) |
| Same 5 failing tests on `main` | `ef17e0a` | 4 fail identically (pre-existing); `ProgressUITests.testSavedGoalsWeightWorkoutAndReportsSurviveRelaunch` passed |
| `testSavedGoalsWeightWorkoutAndReportsSurviveRelaunch` after restoring its back-navigation line | `30f0de7` | passed (270 s) |
| Review-fix coverage: `CoachReplyUITests` (4), Progress weight/workout Ask Pip, Log with Pip, largest text | `30f0de7` | 8 tests passed |
| Diary toolbar change: 7 Diary/Coach tests that use `diaryAskPip` / the `+` menu | toolbar commit (working tree on `30f0de7`) | 7 tests passed |

**Pre-existing failures (fail the same way on `main` `ef17e0a`, not caused by this branch):**
`DiaryUITests.testCapturePhotoReviewCorrectionEditingAndHistory` ("Focused meal details must hide the tab bar"),
`ManualNutritionUITests.testManualCancelAndSavePreserveUnsentNoteDraft`, `testManualFormSupportsLightDarkAndLargestTextSave`,
`testOfflineTodayCreateAndAppendRemainSavedAfterRelaunch` (keyboard focus / reveal of `manualCalories`).

`CoachUITests.testFixtureMealCorrectionHistoricalReviewAndConversationRelaunch` needs about 174 s; it passed with a 300 s execution allowance and exceeds the default 60 s one.

## Device

Release build of `30f0de7` built with automatic signing, installed over the existing app (data kept) and launched on the iPhone 15 Pro. This confirms build, install and launch only.

## Not verified

VoiceOver and swipe gestures on the new Progress Ask Pip actions (only the context-menu path has a UI test); the quick-log toast "Add Note" Coach path has no UI test; no full UI suite run.
