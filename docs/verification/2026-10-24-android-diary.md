# Android Diary tab and meal detail verification

Recorded 2026-10-24. Plan: Android Diary and meal detail (plan 3b).

- Source SHA tested: `fa5505f91b9889e1d2e645fee7e396c66de34834` (branch `docs/android-design`, clean tree).
- Environment: macOS 27.0.1, Android Studio JBR, Gradle 9.8.2; emulator `Medium_Phone_API_37.0`
  (emulator-5554, API 37) for instrumented tests. Counts are summed from the JUnit result XML.
- Command (one run, `--rerun-tasks`):

  ```sh
  cd android && ./gradlew :app:testDebugUnitTest :app:connectedDebugAndroidTest :app:lintDebug :app:assembleRelease --rerun-tasks
  ```

- Result: BUILD SUCCESSFUL.
  - `:app:testDebugUnitTest`: 135 tests, 0 failed, 0 errors, 0 skipped.
  - `:app:connectedDebugAndroidTest`: 135 tests, 0 failed, 0 errors, 0 skipped.
  - `:app:lintDebug` and `:app:assembleRelease` passed.

## Covered tests

- Diary tab: `DiaryViewModelTest` (JVM), `DiaryScreenTest` (week strip, day selection, meal rows), `DiaryDaysTest`,
  `DiaryQueriesTest`.
- Meal detail: `MealDetailScreenTest` (foods and totals, delete food, single-food guard, delete meal, photo viewer
  delete keeps the meal, mark reviewed, deleted meal unavailable, add food manually).
- Editors: `MealEditorsTest` (edit food, stale edit message, adjust total, move meal receipt, recreate).
- Store semantics: `MealEditsTest` (item recompute, review proposal, last-item guard, scale to target, photo delete,
  move meal totals, tombstoned day, stale revision).

## Screenshots

`docs/verification/android-diary/`: `diary-light.png`, `diary-dark.png`, `diary-large.png`, `diary-large-meals.png`,
`meal-light.png`, `meal-dark.png`, `food-editor-light.png`, `scale-light.png`, `move-light.png`.

## Not covered

- Ask Pip waits for Coach (milestone 4); weight and workout manual entry arrive with the milestone 6 editors.
- Only the first tracking day per date is shown; the "Record history" disclosure is not ported.
- The Diary saved-meal receipt is not shown and "Log meal" for a chosen day is not available.
- "Add note or photo" (correction capture) on meal detail waits for Coach and the composer.
- No hosted CI run is claimed; release build not run on a device.
