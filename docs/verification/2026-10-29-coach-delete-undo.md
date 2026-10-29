# Coach delete Undo and food-row delete — verification

- Branch: `feat/coach-delete-undo`. Base: `main` @ `8dc3a327`.
- Tested source: `5057b08fdcdc0b12ae3a2c4c25cd6d6b11dd4904`. This commit only adds this record.
- Runner: `xcodebuildmcp simulator test`, scheme `Mivu`, test plan `Mivu`, Debug, local Xcode at `/Applications/Xcode.app`.
- Simulators: iPhone 17 Pro on iOS 26.5 (`42CE2315…`) and iOS 27.0 (`DD662DAB…`).
- Spec: `docs/superpowers/specs/2026-10-29-coach-delete-undo-design.md`
- Plan: `docs/superpowers/plans/2026-10-29-coach-delete-undo.md`

## Results

| Run | Scope | Result |
|---|---|---|
| Full unit suite, iOS 26.5 | `MivuTests` | 1261 passed, 12 failed, 1 skipped |
| Environment re-run, iOS 27.0 | `AppleInferenceTests`, `FoodSourceTests`, `CompanionMountTests` | 17/17 passed |
| New behaviour | `CoachDeleteUndoTests` (17 tests) | 17/17 passed |
| Delete-receipt UI | `CoachUITests/testCoachDeletedWorkoutShowsUndoAndRestores`, `testReceiptUndo` | 2/2 passed |
| Food-row UI | `DiaryAmountEditorUITests` (9, including the 2 new tests) | 9/9 passed |
| Food-row tap regression | `DiaryUITests/testCapturePhotoReviewCorrectionEditingAndHistory` plus 3 `CoachCorrectionUITests` | 4/4 passed |

**The 12 iOS 26.5 failures come from the environment, not from this change.**

- 11 of them report "Apple inference requires iOS 27".
- 1 is the `CompanionMountTests` rig-mount timing check.

All of them pass on the iOS 27 simulator, and none of them touch the files this branch changes.

## Not run

- The full UI suite was not run. Only the affected UI tests above were run.
- Physical-device behaviour and Release signing were not verified.
- The 10-minute window was checked with an injected clock, not a real wait.
