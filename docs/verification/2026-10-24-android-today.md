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

## Review fixes

- Source SHA tested: `30f29e64f82830c8ade6c3a5391eb0d8585c960e` (same environment and command as above, one run,
  `--rerun-tasks`). Result: BUILD SUCCESSFUL.
  - `:app:testDebugUnitTest`: 127 tests, 0 failed, 0 errors, 0 skipped.
  - `:app:connectedDebugAndroidTest`: 101 tests, 0 failed, 0 errors, 0 skipped.
  - `:app:lintDebug` and `:app:assembleRelease` passed; `scripts/ci/parity.py` and the `scripts/ci` unit tests passed.
- New tests: `TodayScreenTest.failedReadOffersTryAgainAndKeepsTheLastGoodDay` (synthetic undecodable head) and the
  day-actions semantics in `everyTagExists`; `ManualNutritionScreenTest.blankNutrientsReadUnknownAndNameErrorWaitsForLeaving`
  and the inert receipt in `saveCreatesMealShownOnToday`; `MealComposerScreenTest.moreThanEightPhotosSaysTheLimit`,
  `transparentPhotoIsFlattenedOntoWhite`, `noteIsCappedAtTheStoreLimit`, `racedSaveIsRetriedOnce`,
  `changedDraftAfterAnUnconfirmedSaveIsNotReturnedAsTheOldMeal`.
- `manual-light.png` and `manual-dark.png` re-captured (blank nutrients now show "Unknown" as supporting text).

## Process death

Run `scripts/android/kill_restore_check.sh` (debug APK at the SHA above, emulator `Medium_Phone_API_37.0`). It clears
the app's data, then for each flow: fills the draft, presses Home, waits 2 s, runs `adb shell am kill com.yakov103.mivu`
until the process is gone, and reopens the existing task with `am start -n com.yakov103.mivu/.MainActivity`.

- Manual entry (Today > Add manually, "Synthetic apple", 95 kcal): "Enter nutrition" reopened with both values.
- Composer (sample mode, Today > Log meal, "Synthetic tea", one synthetic PNG picked in the system photo picker,
  "Review before saving totals" on): "Log meal" reopened with the note, "Attached meal photo 1" and the toggle on.
- Result: `PASS`, no app change needed. Note: reopening with the launcher intent after a task first started by
  `am start` (no LAUNCHER category) makes Android start a new task without saved state; that is a test-harness
  artefact, so the script reopens the task itself.

## Not covered

- Pip art is static; the morning check-in and weight row are not built.
- No "Set a goal" or "Edit goals" entry; meal rows are not tappable (no meal detail).
- Food editor, adjust total and move meal are not built.
- Camera capture is not built.
- `MaterialExpressiveTheme` and `MotionScheme` are internal in the resolved material3 1.4.0, so the theme stays
  `MaterialTheme`; the Today kcal change uses Compose's default springs, which honour "Remove animations".
- Release builds not run on a device; no hosted CI run is claimed for these results.
