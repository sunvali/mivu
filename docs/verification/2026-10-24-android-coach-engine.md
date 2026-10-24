# Android Coach engine verification

Recorded 2026-10-24. Plan: Android Coach engine (plan 4a).

- Source SHA tested: `f7e2c830da16f5706285dff5a06b4714c882be1b` (branch `docs/android-design`, clean tree).
  CoachWorkerTest (5/5) and CoachEngineTest (10/10) were re-run at `753c2388`, which includes the
  worker fix `f829f5f0`, with 0 failures.
- Environment: macOS 27.0.1, Android Studio JBR, Gradle 9.8.2; emulator `Medium_Phone_API_37.0`
  (emulator-5554, API 37) for instrumented tests. Counts come from the JUnit result XML.
- Scope: focused Coach classes only. The full connected suite was not run, per the owner.
- Commands:

  ```sh
  cd android
  ./gradlew :app:testDebugUnitTest --tests '*CoachToolsTest' --tests '*CoachReplyCheckTest' --tests '*ResponsesClientTest' --rerun-tasks
  # one run per class; a comma-separated class list only runs the first class
  ./gradlew :app:connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=com.yakov103.mivu.<package>.<Class>
  ```

- Result (all 0 failed, 0 errors, 0 skipped):

  | Class | Tests |
  |---|---|
  | `ResponsesClientTest` (JVM) | 12 |
  | `CoachToolsTest` (JVM) | 12 |
  | `CoachReplyCheckTest` (JVM) | 2 |
  | `CoachContextTest` | 9 |
  | `CoachReadsTest` | 4 |
  | `CoachWritesTest` | 18 |
  | `CoachProgressWritesTest` | 4 |
  | `CoachEngineTest` | 10 |
  | `CoachWorkerTest` | 5 |

- Note: a first sequential pass of the six instrumented classes had failures in `CoachReadsTest`, `CoachWritesTest`,
  `CoachEngineTest` and `CoachWorkerTest` (the worker one was "no diary"). A second pass at the same SHA, with
  no code change, passed every class. The first pass followed a run of the same classes on the same emulator, and
  earlier task reports saw emulator install conflicts. The cause was not isolated.

## What was ported

- Turn storage: Coach turn state, undo rows, finish and fail transitions (`DiaryCapture.kt`, `DiaryDatabase.kt`).
- Bounded Coach context (`CoachContext.kt`): 14-day window, 8,192-byte receipt cap, 60,000-byte context cap (65,536-byte cap on stored Coach JSON), no full snapshot.
- Tools: declarations, strict parsing, fingerprints checked against iOS golden fixtures (`CoachTools.kt`).
- Reads, meal and progress writes, undo (`CoachReads`, `CoachWrites`, `ProgressWrites.kt`).
- Engine (`CoachEngine.kt`): up to 8 rounds and 16 calls, photo limits, ungrounded-claim guard, clarification rule, reply lines.
- Worker (`CoachWorker.kt`): oldest pending turn first, 1/2/4 s backoff, resumes when the network returns, vision photo copies.
- Debug "Run Coach turn" button on the connection proof screen.

## Known shortcuts (marked `shortcut:` in code)

- `delete_workout` keeps photo copies in turns whose only progress was that workout, until Android has `record_source`.
- `find_meals` with an empty description uses the earliest turn naming the meal, not the iOS `record_source` origin.
- `attachedPhotoIDs` uses `turn.photoIDs`; iOS lists resolved photo references.
- Weight write normalization and the unconfirmed-time parse approximate iOS.
- The model is the first entry in the plan's catalog, kept for the process lifetime; there is no model picker.
- Reply summary numbers approximate Swift's Double formatting; output items are valid JSON but not byte-identical to iOS.
- The worker does not move an analyzing turn back to captured, and has no legacy-capture recovery.

## Not covered

- The full connected suite was not run, per the owner.
- The live Coach turn against ChatGPT is blocked until the owner signs in on the emulator (Phase 0).
- There is no Coach UI yet; it comes in milestone 4b.
- Only the food "Saved — about N kcal." summary line is tested; the undo, scale, move, photo, weight, workout, goal
  and day-coverage lines are ported but not compared with iOS.
- No hosted CI run is claimed.
