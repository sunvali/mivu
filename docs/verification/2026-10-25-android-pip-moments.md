# Android Pip moments verification

Recorded 2026-10-25. Plan: [Android Pip moments](../superpowers/plans/2026-10-25-android-pip-moments.md) (milestone 7),
milestone close.

- Source SHA tested: `cca3e860bc68809d352ed6d3ae877f7e416221fe` (branch `docs/android-design`, clean tree).
- Environment: macOS 27.0.1, Android Studio JBR, Gradle 9.8.2; emulator `Medium_Phone_API_37.0` (emulator-5554,
  API 37), time zone Asia/Jerusalem, Sunday. Counts are summed from the JUnit result XML; a skipped, assumption-stopped
  or zero-test class is not counted as passing.
- Command (one run, `--rerun-tasks`), 17:46–18:01 local time:

  ```sh
  cd android && ./gradlew :app:testDebugUnitTest :app:connectedDebugAndroidTest :app:lintDebug :app:assembleRelease --rerun-tasks --continue
  ```

- Result: BUILD FAILED in 15 min 37 s (`connectedDebugAndroidTest` only).
  - `:app:testDebugUnitTest`: 318 tests in 40 classes, 0 failed, 0 skipped.
  - `:app:connectedDebugAndroidTest`: 414 tests in 49 classes; 410 passed, 4 failed:
    - `CoachHistoryScreenTest.mealAskPipSeeksSourceTurn` (10 of 11): times out waiting for the highlighted source
      turn. It fails the same way at `9987338b`, before any milestone 7 screen change (rerun of that one method in a
      separate worktree), so it is not caused by this milestone; cause not established. It passed in the milestone 6
      record. Carried.
    - `TodayScreenTest.logWithPipSelectsCoach` (13 of 14): asserts the Coach tab is selected right after "Log with
      Pip" leaves the screen, without waiting. The class rerun alone at the same SHA passed 14 of 14. A flaky wait,
      not counted as a pass. Carried.
    - `MorningCheckInTest.deniedNotificationPermissionExplainsTheOffSwitch` (12 of 13): stopped on its assumption
      ("permission already granted on this install"), as in the milestone 6 record.
    - `MorningCheckInSeed.seedMorningFixture`: a seed class that stops on its assumption. It ran although
      `build.gradle.kts` lists it under `notClass`; not counted. Carried.
  - `:app:lintDebug`: 0 errors, 23 warnings, 1 hint. An earlier full run at `0e18caaa` had 24 warnings; the new one
    (`UseKtx` on `CompanionLastActive.record`) is fixed in `cca3e860`.
  - `:app:assembleRelease`: passed.
- An earlier full run at `0e18caaa` (before the lint fix) gave the same unit and connected totals with 3 failures
  (`mealAskPipSeeksSourceTurn` and the two assumption stops); its per-class XML was overwritten by focused reruns, so
  this record uses the `cca3e860` run.
- `python3 scripts/ci/parity.py` passed, and `python3 -m unittest discover -s scripts/ci -p 'test_*.py' < /dev/null`
  ran 53 tests OK.

## Named tests (all passed in the run above)

Task 1, presentation (`android/app/src/test/.../pip`):
- `CompanionPresentationTest` 18/18: welcomeBackOnceAfterADayAway, sameDayReturnGreets, enterBackgroundGreetsAgain,
  habitAndReviewKindsPlayTheirPoses, firstMealReplacesAPlayingSaved, staticPlaybackDropsAPendingMoment,
  pendingMomentExpiresAfterTheLifetime, processingInterruptsWelcomeBack, savedEventCarriesNoAmount.
- `PipGestureLibraryTest` 8/8 (heartsAlwaysPopToScaleOne), `CompanionRuntimeTest` 7/7, `MotionPolicyTest` 6/6.

Task 2, Today (`android/app/src/androidTest/.../ui`):
- `TodayCompanionTest` 5/5: firstMealPlaysOnceAfterTheComposerReturns (the capture's saved event survives a covering
  composer and closing it does not greet again), secondMealIsSavedOnly, reviewedPlaysOncePerSubmission,
  foregroundOnALaterDayWelcomesBack (also checks that `enterBackground` records `CompanionLastActive`),
  backgroundAndBackGreetsAgain.
- `TodayScreenTest`: pipStopsWhenScrolledAwayAndResumes, and pipHoldsStillBelowHalfVisible (40% of Pip visible is
  Hidden, 60% is Animated, with Pip still composed).
- `ReviewedOriginTest` 2/2: meal detail opened from Today reaches Today; opened from Diary it does not, although
  Today stays in the back stack.
- Moved wiring: `MorningCheckInTest` (12/13, assumption stop above), `MealDetailScreenTest` 11/11,
  `CoachComposerTest` 21/21.

Video: a 10 s `screenrecord` of Today saving a manual meal, with the saved moment and no re-greet on return (84 frames,
5.7 s of change), kept outside the repository with the Task 2 report.

## Decisions
- Day complete is not wired: iOS defines the pose, kind and gesture but nothing emits it. Parity, carried to Later.
- `characterChanged` is `n/a`: Android has no character selection.
- Heart pop: no change; pinned by `heartsAlwaysPopToScaleOne`.
- Welcome back plays on Today only; Coach gets the re-greet after the background, not welcome back, so one return
  does not play it twice.
- Reviewed reaches Today only when meal detail was opened from Today (`todayOrigin()`, the previous back-stack entry).
- A rotation is not the background: Today and Coach skip `enterBackground` while the activity changes configuration.
- `rememberMotionPlayback` reads the animator scale, power save and thermal status again after registering its
  listeners, so a change in between is not lost (a race; no test pins it).

## Limits
- Pip's frame rate still needs an idle host or a real phone (Play readiness, unchanged).
- Coach re-greets only when the app was backgrounded while Coach was composed; its model is activity-scoped.
