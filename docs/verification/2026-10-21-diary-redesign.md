# Diary redesign — native verification

Date: 21 October 2026. Branch `feat/diary-redesign`, rebased on `main` `8059a5d`.
Environment: Xcode 27.0, iOS 27 simulator "iPhone 18 Pro" (dedicated device
`FC4BDE77-679D-4AB6-B045-B317E6541781`), `-testPlan Mivu`, serial testing.
Spec: [design](../superpowers/specs/2026-10-20-diary-redesign-design.md),
plan: [implementation plan](../superpowers/plans/2026-10-20-diary-redesign.md).

## Full suite

Source `a57a588`: **1101 passed, 10 failed, 1 skipped.**

| Failure | Classification |
| --- | --- |
| DiaryUITests `testCapturePhotoReviewCorrectionEditingAndHistory` | Fails identically on `main` `8059a5d` after midnight (late-meal receipts push the Today row under Log meal) |
| DiaryUITests `testLegacyHebrewLaunchUsesEnglishLeftToRight` | Fails identically on `main` (no "Diary preferences" button) |
| DiaryUITests `testUnsavedSettingsRequireExplicitDiscard` | Fails identically on `main` (same) |
| DiaryUITests `testMealPhotoViewerClosingAndCancelledDeletionPreserveRecord` | Fails identically on `main` after midnight |
| ManualNutritionUITests `testOfflineTodayCreateAndAppendRemainSavedAfterRelaunch` | Fails identically on `main` after midnight |
| CoachUITests `testLargestDynamicTypeDarkCoachKeepsCaptureReachable` | Fails identically on `main` |
| CompanionUITests `testLargestTextLightAndDarkKeepPrimaryActionsReachable` | Fails identically on `main` |
| CompanionUITests `testRigReferenceCompositionsAndHorizontalComposerInBothAppearances` | Fails identically on `main` (116 > 110 pt) |
| ProgressUITests `testSavedWorkoutSetsAndNoGoalReport` | Fails identically on `main` |
| CompanionUITests `testFallbackKeepsCaptureAndReviewUsable` | **Branch regression** — Mark reviewed hidden under the new Ask Pip bar; fixed in `4508586` |

Unit test `CoachEngineTests.requestedProgressRereadsFactsAfterSuspendedInference`
also fails on `main` `0b8f4d3` in multi-suite runs (timing); it passed in this run.
Baselines were run on unmodified `main` checkouts on separate dedicated simulators.

## After the full run

Review fixes and the regression fix were verified with focused runs, not a second full run:

| Commit | Run | Result |
| --- | --- | --- |
| `a5bf42d` review fixes (delete guards, stale week, strip range) | DiaryDeleteItemTests, DiaryWeekStripTests, CoachManualEngineTests, CoachEditParityTests | 31/31 |
| same | Diary week-strip UI tests, DiaryAmountEditorUITests, SummaryCardsUITests, historical manual entry | 15/15 |
| `4508586` Mark reviewed pinned | CompanionUITests fallback, CoachCorrectionUITests, Coach historical review, CoachNavigationUITests | 12/12 |
| `0afbfbd` sheet title and delete tint | DiaryAmountEditorUITests | 6/6 |

## Screens

Captured from the simulator at `0afbfbd` with the 75-day synthetic history fixture:
[Diary light](diary-redesign/diary-light.png), [Diary dark](diary-redesign/diary-dark.png),
[Diary at accessibility XXXL](diary-redesign/diary-largest-text.png),
[meal light](diary-redesign/meal-light.png), [meal dark](diary-redesign/meal-dark.png),
[food edit sheet](diary-redesign/food-edit-light.png).

## Not verified

- Physical-device VoiceOver, haptics and Dynamic Type; simulator only.
- The after-midnight Today layout (receipts pushing the meal row under Log meal) is a pre-existing Today issue, not addressed here.
- The pre-existing `main` failures above were not investigated.
