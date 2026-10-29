# Android Gemini Nano verification

Recorded 2026-10-29. Spec: [Android Gemini Nano](../superpowers/specs/2026-10-29-android-gemini-nano-design.md).
Plan: [Android Gemini Nano](../superpowers/plans/2026-10-29-android-gemini-nano.md).

- Tested source SHA: `05e6146d` (`05e6146dd42778f5d2457389f00a8bc5b9ffb713`), branch `docs/android-design`. This commit changes docs only.
- Environment: macOS 27.0.1, Android Studio JBR, Gradle via `./gradlew`; emulator-5554 (`Medium_Phone_API_37.0`, API 37).
- Counting rule: counts are from the task runs; a class that failed is listed as failed.
- Commands: `./gradlew :app:testDebugUnitTest :app:lintDebug`, and `:app:connectedDebugAndroidTest` with `-Pandroid.testInstrumentationRunnerArguments.class=<class>` on emulator-5554 only. No full connected suite was run.

## Results by task

| Task | Commits | Result |
|---|---|---|
| 1 FNDDS table | `0ecf4705`, `a70ab82d`, `de2fb788`, `3dd49897` | `NutritionTableTest` 4/4 (emulator); `NutritionWordsTest` passed; `scripts/ci` contract tests 8 OK; `test_build_fndds` 1 OK; JVM 350/0 at first commit |
| 2 On-device turn | `56a40d5e` | `OnDeviceInferenceTest` 18/18; JVM 368/0; lint clean |
| 3 Model and provider | `4b8d4205`, `987e5b5e` | `CoachProviderTest` 9/9, `GeminiNanoTest` 2/2, `ChatGPTConnectionTest` 17/17; JVM 379/0; lint 0 errors |
| 4 Foreground only | `3886d5c8`, `01d6b4c0`, `1a471379` | `OnDeviceCoachTest` 6/6, `CoachWorkerTest` 15/15, `CoachJobServiceTest` 5/5, `TellCoachTest` 8/8 (emulator) |
| 5 Settings, onboarding, Coach | `45834959`, `05e6146d` | `OnDeviceSettingsTest` 7/7, `ConnectionScreenTest` 12/12, `OnboardingScreenTest` 18/18, `MealDetailScreenTest` 11/11, `MorningCheckInTest` 13/13 (emulator); JVM 384/0 after the download fix; lint OK |

## Not passing or not run

- **Live Nano check: blocked.** No supported device: the Pixel 8 Pro and the emulator report UNAVAILABLE. Every Nano result above uses a fake `OnDeviceModel`, so the real model, its download and its output are unverified.
- **`CoachComposerTest` 24 of 27.** Three pre-existing time-of-day failures, outside this change: `bubbleSpansTheComposerWidth`, `committedSendWithClearedCacheCountsAsSent` and `idleBubbleGreetsAndChipOpensToday`. At 02:10 the app shows "Yesterday ·" instead of "Today ·". Not run against the baseline.
- No full connected suite and no release build for this change.

## Dependencies

- `com.google.mlkit:genai-prompt` is pinned at `1.0.0-beta5` (beta; the latest on Google Maven on 2026-10-26).
- ML Kit raises `kotlinx-coroutines` to 1.11.0 at runtime (declared 1.9.0) and adds Play services transport libraries.

## Play

Nothing was submitted to Play. The 18+ audience and the ML Kit Data safety entry are drafts for the owner to confirm ([Play submission](../development/play-submission.md)).
