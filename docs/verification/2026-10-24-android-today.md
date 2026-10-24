# Android app shell, Today, manual entry and sample mode verification

Recorded 2026-10-24. Plan: Android app shell and Today (plan 3a).

- Source SHA tested: `abfa2d9321b372680d2eaa1345966dd364599da9` (branch `docs/android-design`, clean tree).
- Environment: macOS 27.0.1, Android Studio JBR, Gradle 9.8.2; emulator `Medium_Phone_API_37.0`
  (emulator-5554, API 37) for instrumented tests. Counts are summed from the JUnit result XML.
- Command (one run, `--rerun-tasks`):

  ```sh
  cd android && ./gradlew :app:testDebugUnitTest :app:connectedDebugAndroidTest :app:lintDebug :app:assembleRelease --rerun-tasks
  ```

- Result: BUILD SUCCESSFUL.
  - `:app:testDebugUnitTest`: 127 tests, 0 failed, 0 errors, 0 skipped.
  - `:app:connectedDebugAndroidTest`: 94 tests, 0 failed, 0 errors, 0 skipped.
  - `:app:lintDebug` and `:app:assembleRelease` passed.

## Covered tests

- Today: `TodayViewModelTest` (JVM), `TodayScreenTest` (summary tags, unknown values, start new day,
  Add manually, Log with Pip, 2x font scale).
- Manual entry: `ManualNutritionDraftTest` (JVM), `ManualNutritionStoreTest`, `ManualNutritionScreenTest`
  (save, discard dialog, recreate, double save, process death).
- Sample mode: `SampleAnalyzerTest` (JVM), `MealAnalysisWorkerTest`, `MealComposerScreenTest`
  (text-only save shows the sample apple on Today, empty save disabled, review first, photo picker result).

## Screenshots

`docs/verification/android-today/`: `today-light.png`, `today-dark.png`, `today-large.png`,
`manual-light.png`, `manual-dark.png`, `composer-light.png`, `composer-dark.png`.

## Not covered

- Pip art is static; the morning check-in and weight row are not built.
- No "Set a goal" or "Edit goals" entry; meal rows are not tappable (no meal detail).
- Food editor, adjust total and move meal are not built.
- Camera capture is not built.
- Release builds not run on a device; no hosted CI run is claimed for these results.
