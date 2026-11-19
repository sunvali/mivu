# Onboarding rework — verification

Spec: [onboarding rework](../superpowers/specs/2026-11-19-onboarding-rework-design.md).

- **Source:** `fe51abd04799b7de9939a7e5d5a5cebd38e043f9` (branch `feat/onboarding-rework`, based on `a024ed1d`).
- **Environment:** local Xcode on macOS 27.0.1. iPhone 17 Pro simulator, iOS 27.0, freshly created for these runs. Debug build.

## Final focused run at the source SHA

Result: 19 passed, 0 failed, 0 skipped.

- `MivuTests/OnboardingTargetsTests`: all 14, including the new tests:
  - `activityChangesTheEstimateAndAMissingOneStaysLight`
  - `theFloorDependsOnSex`
  - `fasterIsCappedAtOnePercentOfBodyWeightAWeek`
  - `pregnancyKeepsWeightWhateverTheGoal`
  - `goalDateFollowsTheRealEnergyGap`
  - `aReplyUnderTheFloorIsRejectedAndThePromptStatesIt`
  - `savedAboutWithoutActivityStillDecodes`
- `MivuTests/OnboardingSetupSaveTests`
- `MivuUITests/DiaryUITests`:
  - `testFirstRunOpensSetupWithoutInventingRecords`
  - `testSetupHidesTuneForAPlanThatCannotConnect`
  - `testRedoSetupFromSettingsKeepsKeyboardDone`
- `MivuUITests/ProgressUITests/testFilledGoalLabelsAndClearingLastTargetSurviveRelaunch`

## Earlier runs on this branch

These ran on `fe51abd0`'s parent work, before the Tune shortcut and the accessibility-size layout fixes.

- **`MivuTests`, full:** 1,535 passed, 15 failed, 1 skipped.
  - The same 15 failures (Coach date and progress prose tests) also fail on unchanged `main` (`a024ed1d`). That run gave 1,527 passed and 16 failed on a fresh simulator, so they are pre-existing.
  - Onboarding and weight-editor tests all passed.
- **UI, 8 of 8 passed:**
  - the three onboarding tests above;
  - `ProgressUITests`:
    - `testEachCardOpensItsDetail`
    - `testFilledGoalLabelsAndClearingLastTargetSurviveRelaunch`
    - `testSavedGoalsWeightWorkoutAndReportsSurviveRelaunch`
    - `testWeightChartSelectsSavedMeasurement`
  - `LanguageSweepUITests/testPrimaryActionsStayHittable`.
- **Pre-existing, unrelated:** `DiaryUITests/testCapturePhotoReviewCorrectionEditingAndHistory` fails at the meal composer's Cancel lookup on both this branch and unchanged `main`.

## Manual checks on the simulator

- **Ruler drag:** a drag moved 170 → 179 cm and a fling moved 70.0 → 78.3 kg. Each snapped to a tick.
- **Units:** cm ↔ ft/in and kg ↔ lb convert the value.
- **Live pace rows:** 12.1 kg at 0.5 kg a week reads "by May 2027". The male 1,500 kcal floor shows on Faster.
- **Pregnancy chip:** shows the hold note.
- **Saved targets:** Save lands on Today with the goal set.
- **Dark mode:** the whole flow.
- **Largest accessibility text size:**
  - Ruler labels capped.
  - The kcal number and unit stack.
  - Tune moves into the page.

## Not covered

- Live ChatGPT tuning. It needs a real account, and tests use synthetic inputs only.
- VoiceOver's adjustable ruler on a device. XCUITest can't send iOS adjust actions.
- Hebrew, Spanish and Russian text. It was checked only by `languages.py`.
- The full UI suite. It wasn't run, by the owner's preference for focused runs.
- Android. It follows in a later PR.
