# Coach context — native verification

Date: 21 October 2026. Branch `feat/coach-context`, based on `5017ea4`
(`feat/coach-reply`, PR #39). HEAD `f6f4541f`.
Environment: Xcode 27.0, iOS 27 simulator "Mivu-coach-context" (dedicated device
`B5922D8D-CBEA-4F05-9F27-5801AD5726A0`), `-testPlan Mivu`, serial testing,
`-collect-test-diagnostics never`.
Spec: [design](../superpowers/specs/2026-10-21-coach-context-design.md),
plan: [implementation plan](../superpowers/plans/2026-10-21-coach-context.md),
behavior: [Coach chat behavior](../development/coach-chat-behavior.md).
Per the owner, only needed tests were run; this record is assembled from those runs.

## Focused runs per task

| Task | Commit | Run | Result |
| --- | --- | --- | --- |
| 1 History as messages | `0af619b` | CoachContextMessagesTests (3), CoachEngineTests, CoachManualEngineTests, CoachCorrectionJourneyTests; fixture-inference fix: Goals/Weight/Workout, Thinking-follows-latest, MealCorrection UI tests | 67 unit passed; the 3 UI tests passed after the fixture fix |
| 2 Focus | `4899517` | CoachFocusTests, CoachEngineTests, CoachIndexedContextTests, CoachStoreTests, CoachContextMessagesTests | passed |
| 3 Clarification | `8f2f800` | CoachClarification/Engine/ManualEngine/Focus/Reply/IndexedContext/ContextMessages; CoachEditParity/CorrectionJourney/DiaryProjectionIntegration/CoachStore/CoachTimeline | 90 + 103 passed |
| 4 Partial success | `e755fb4`, `8c6897a` | CoachPartialSuccessTests (2 + cancellation and photo-only cases), CoachEngineTests, CoachFlowTests; UI `testPartialSuccessShowsSavedCardAndRetry` | 60 passed; UI passed |
| 5 Chips | `4fe45a2`, `4a0845a` | CoachClarificationUITests (3), CoachHistoryWindowTests, CoachReply and CoachCorrection UI classes | 3/3 UI; 11 UI executed, 0 failures; window suite passed |
| 6 Scale meal | `7d3e3b1`, `7cf6bb0` | CoachScaleMealTests (8), CoachEditParityTests, CoachManualEngineTests, DiaryDeleteItemTests; UI `testAdjustMealTotal` | 35 passed; UI passed |
| 7 find_meals | `1abda0e` | CoachFindMealsTests (3), CoachEngineTests, CoachIndexedContextTests, ResponsesClientTests, CoachContextMessagesTests, CoachEditParityTests | 111 passed in 6 suites |
| 8 Undo | `77638d5`, `9c409c9` | CoachUndoTests (8 after fix), CoachBatchTransactionTests, CoachRecoveryReviewTests, CoachEditParityTests, CoachEngineTests, CoachScaleMealTests, DiaryMigrationTests, DiaryTests; UI `testReceiptUndo` | 127 passed in 8 suites; UI passed |

Task 7 raised the tool-catalog sanity cap from 32 to 40 (local check, not a
provider limit). Task 4 changed about 12 existing tests that expected a throw
after a write; they now assert the turn completes as incomplete and reopen it to
keep their replay intent.

## Full MivuTests

Source `ae6d721` (before the two later fixes): **1085 tests in 107 suites, 11 issues.**

| Failure | Classification |
| --- | --- |
| CoachAttachmentDraftTests, two `...DuringFailedFinalRefresh...` tests (10 issues) | Test double scanned history user messages; fixed in `f6f4541`, then 27/27 passed |
| CompanionRootIntegrationTests `pagingAndPhotoLoadsEmitNoCompanionFeedback` (1 issue, `:84`) | Not classified; not rerun |

They failed from Task 1 (`0af619b`) on, so the implementers' stash checks were mid-branch; a run on base `5017ea4` was attempted but executed 0 tests and is not evidence.

## Partial UI run

`MivuUITests` was started as a whole and stopped at the owner's request after
the Coach classes: 32 results (28 passed, 4 failed), source `ae6d721`.
Classes run: CoachAccessiblePagingUITests, CoachActivityUITests,
CoachClarificationUITests, CoachCorrectionUITests, CoachHistoryUITests,
CoachNavigationUITests, CoachReplyUITests, CoachScrollSpikeUITests, and part of
CoachUITests (stopped at `testLargestDynamicTypeDarkCoachKeepsCaptureReachable`).

**Not run:** the rest of CoachUITests, CompanionUITests, DiaryAmountEditorUITests,
DiaryUITests, ManualNutritionUITests, ProgressUITests, QuickLogUITests,
RootTabNavigationUITests, SmokeUITests, SummaryCardsUITests.

## Head vs base regressions

Targeted runs of the four failing tests (head `ae6d721`, base `5017ea4`):

| Test | Head | Base | Cause and fix |
| --- | --- | --- | --- |
| CoachCorrectionUITests `testYesterdayLunchCorrectionUsesGroundedUnloadedMealExactlyOnce` | failed | passed | Undo added a 44-pt row, so receipt cards grew about 48 pt and the meal link sat under the navigation bar |
| CoachHistoryUITests `testYesterdayLunchCorrectionShowsCommittedTotalAndTargetDate` | failed | passed | same |
| CoachReplyUITests `testSwipeReplyQuotesPipSendsAndQuoteSeeksOriginal` | failed | passed | same, first exchange pushed out of the table |
| CoachNavigationUITests `testColdDiarySourceRouteBeforeCoachMountOpensExactSource` | passed | passed | failed once in the full run; flake (cold source) |

Fix `6fb9b6f`: Undo moved into the receipt header row. Rerun of the three plus
`testReceiptUndo`: 4 tests, 0 failures.

Earlier, three CoachUITests (Goals/Weight/Workout, MealCorrection, Thinking follows
latest) passed at base and failed at `0af619b` and `8f2f800`; the cause was the
UI-test inference reading history user messages as the current capture. Fixed in
`ae6d721`, then passed in the full UI run. `testFixtureMealCorrectionHistoricalReviewAndConversationRelaunch`
failed 3 of 6 earlier runs at `:147` (send button hit point {-1,-1}) and passed
in the others and in the full run; treat as flaky.

`f6f4541` (test-only) fixes the attachment double: CoachAttachmentDraftTests 27/27.

## Not verified

- The remaining UI classes listed above, and a second full MivuTests run at HEAD.
- Undo row fallback (status too long) and accessibility-size layouts; no screenshot review.
- VoiceOver on a physical device; simulator only.
- On-device replay of the spec's three transcripts: BLOCKED pending the owner.
- `pagingAndPhotoLoadsEmitNoCompanionFeedback` failure was not investigated.
