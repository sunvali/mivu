# Android Coach delete Undo and visible food delete verification

Recorded 2026-10-30. Android port of iOS #83. Spec: [Coach delete Undo](../superpowers/specs/2026-10-29-coach-delete-undo-design.md).
Plan: [Coach delete Undo](../superpowers/plans/2026-10-29-coach-delete-undo.md). iOS record: [verification](2026-10-29-coach-delete-undo.md).

- Tested source: `4a0558934b608564a2146e4d9a0f45885f8ff2ee` on branch `docs/android-design` (commits `64da2f3e` and `4a055893`). Every run below used this tree; the commits after it change docs only.
- Environment: macOS 27.0.1, Android Studio JBR, Gradle via `./gradlew`; emulator-5554 (`Medium_Phone_API_37.0`, API 37).
- Commands: `./gradlew :app:testDebugUnitTest :app:lintDebug`, and `:app:connectedDebugAndroidTest` with `-Pandroid.testInstrumentationRunnerArguments.class=<class>`, one class at a time, on emulator-5554 only. No full connected suite was run.
- Counting rule: counts are from the task runs (the instrumented XML result files).

## Results

| Scope | Result |
|---|---|
| JVM `:app:testDebugUnitTest` (includes `CoachToolsTest`, `CoachReceiptPresentationTest`) | 396 passed, 0 failed |
| `:app:lintDebug` | build successful |
| `CoachDeleteUndoTest` (new, 22 tests) | 22/22 |
| `CoachWritesTest` | 18/18 |
| `CoachTimelineTest` | 11/11 |
| `CoachContextTest` | 9/9 |
| `DiaryCaptureTest` | 16/16 |
| `CoachScreenTest` | 22/22 |
| `MealDetailScreenTest` (2 new: `foodRowDeleteButtonConfirmsAndRemovesTheFood`, `foodRowDeleteButtonOnTheOnlyFoodAsksToDeleteTheMeal`) | 14/14 |
| `TodayScreenTest` (2 new: `longPressingAMealDeletesItOnlyAfterConfirmation`, `swipingAMealAsksBeforeDeletingAndKeepsTheRow`) | 16/16 |
| `DiaryScreenTest` (1 new: `longPressingAHistoryMealDeletesItAfterConfirmation`) | 10/10 |

## Failed first

- `CoachDeleteUndoTest`: 19 of 22 failed before the change (no held table, no Undo; the three that passed were controls: `photoUndoRefusedWhenMealGone`, `historyLeavesLiveMealsUnmarked` and `deleteStillHappensWhenThePhoneHasNoRoomForTheCopy`, which could not fail before a copy existed). `voiceUndoRefusedTwoMessagesLater` was corrected to expect `InvalidArguments`, as the second message erases the copy, and then passed.
- `CoachToolsTest.manualEditToolsParse` and the two new `CoachReceiptPresentationTest` cases (`removalsReadRemovedAndOnlyOfferUndo`, `anUndoOfARemovalIsNotLabelledRemoved`) failed before the change.
- `foodRowDeleteButtonConfirmsAndRemovesTheFood` failed with the button switched off (no node "Delete Blueberries"). The other new UI tests, including the three row swipe and long-press cases, were written after the code and not seen to fail first.

## Not passing or not run

- Not run: the full connected suite, a release build, a physical phone, TalkBack by hand, and a visual check of the removal card, the food-row button and the row swipe on a screen.
- The 10-minute window uses an injected clock in the tests, not a real wait.
- The "no room for the copy" rule is tested with a free-space seam, not a full disk.
- `CoachComposerTest` and `OnboardingScreenTest` were not run, so their known time-of-day failures did not appear.

## Deviations from the iOS design

- Android has no diary size quota, so "quota failure" is a free-space check on the phone (twice the held photo bytes plus 1 MiB); a short phone gets the delete without Undo and without the `undo_key` hint.
- The held copy sits in `coach_undo_deleted` and `coach_undo_deleted_photo` (bytes beside the payload, as the record tables). `restoredID` is not stored: the card reads "Undone" from the `undone` flag.
- A meal without foods gets no Undo (a restored meal needs at least one food).
- Photo Undo on Android adds the photo to the meal by its original ID; the meal-gone case throws `NotFound`.
- Long-press on a Today or History meal row opens the delete confirmation directly (iOS shows a one-item context menu first).
- The `undo_change` tool description is unchanged: the declarations are locked to the iOS golden (`declarationsMatchIosGolden`) and iOS did not change the text.
- Days are never deleted on Android, so no day is re-resolved when a meal comes back.
