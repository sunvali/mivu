# Android iOS 1.1.1 Catch-up Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring Android to iOS 1.1.1 (`origin/main` `5afd977f`, merged here
in `2f9dbf25`) for every iOS change merged since the Android baseline that
applies to Android:
- #64: each nutrient adds the foods that know it;
- #66: the model corrects rejected tool batches, one silent retry, and
  `failureReason`;
- #71: a failed turn never stays on "Thinking…";
- #67 and #70: Pip speaks in a bubble with the day intake chip, across the
  composer's full width, and friendly Chat history rows;
- #69: Power Saver no longer holds Pip still;
- archive round trip: `failureReason` survives an Android re-export;
- #46: the chat scrolls behind the floating composer;
- #45: a quoted workout opens the workout;
- `docs/parity.md` rows for everything merged after the baseline.

**Architecture:** Every change is a port of a small, merged iOS diff into the
Android owner that already mirrors it. No new layer:
- **Totals.** All Android totals go through `diary/DiaryMath.kt`
  (`sumOrNull`). Today, the meal and day cards, Progress, the widget, the
  report and the Coach `get_progress` output all call `nutritionTotals`,
  `dayNutritionTotals` or `dailyProgress`. Fixing `sumOrNull` fixes them all.
  The Coach receipt has its own `committedTotal`. Android has no SQL day sum
  (iOS `DiaryDatabaseMealMutations`), so there is no third site.
- **Coach engine.** `CoachEngine.run` splits into `run` (one silent retry)
  and `attempt(isFinal)`, as iOS does. The batch parse and validation get a
  `try` that returns a rejected batch to the model. The failure write stores
  `failureReason`. The first `analyzing` write moves inside the `try`.
- **Worker.** `CoachWorker.pass` settles a turn the engine left `captured` or
  `analyzing` through one new `DiaryDatabase.settleCoachTurn`. This is iOS
  `CoachViewModel.settle`.
- **Composer.** A pure `PipLine` and `coachDayChip` (iOS `PipLine.swift`)
  replace the "Logging to…" caption. The composer draws a bubble and a chip
  above a row holding the field and the round button (iOS #70). `CoachScreen`
  becomes a `Box`: the timeline fills it, and the composer overlays its
  bottom with the iOS 56 dp fade.

**Tech Stack:** Kotlin, Jetpack Compose with Material 3, `kotlinx.serialization`
(`SwiftJson`), `android.util.Log`, and JUnit with Compose UI tests. No new
dependency.

**Spec:** the iOS sources are the spec. Each PR body is quoted in the audit:
- `.superpowers/sdd/ios-catchup-audit.md` (the scope and its evidence);
- the food logger spec rule from #64,
  [`2026-10-11-food-logger-design.md`](../specs/2026-10-11-food-logger-design.md):
  "Each nutrient adds the items that record it and is unknown only when none
  do";
- the Android app design,
  [`2026-10-23-android-app-design.md`](../specs/2026-10-23-android-app-design.md)
  (Coach, Pip and archive rows).

The mockup is
[android-pip-bubble-mockup.png](../../verification/android-design/android-pip-bubble-mockup.png).
It shows idle (light), working with partial calories (light), needs retry
(dark) and not connected (dark).

**iOS sources** (the source of truth; copy is verbatim, with "iPhone"
replaced by "phone"):
- #64 `2ed34e43`: `ios/Mivu/Diary/DiaryModels.swift` `nutritionTotals`,
  `ios/Mivu/Progress/ProgressAnalytics.swift` `daily`, and
  `ios/Mivu/Coach/CoachReceiptView.swift` `committedTotal`.
- #66 `75173ccb`:
  - `ios/Mivu/Coach/CoachEngine.swift` `run`, `attempt`, the correction
    `catch`, `failureReason`, `isCorrectable` and `isModelOutputFailure`;
  - `ios/Mivu/Coach/CoachModels.swift` `CoachTurn.failureReason`;
  - `DiaryModels.swift` `validateCoachTurnFields` (at most 200 bytes).
- #71 `f0c78a4c`: `CoachEngine.swift` (log before the selection check) and
  `ios/Mivu/Coach/CoachViewModel.swift` `settle(_:after:owner:)`.
- #67 `ca8422d1` and #70 `5279293c`:
  - `ios/Mivu/Coach/PipLine.swift`;
  - `ios/Mivu/Coach/CoachView.swift` `companionStrip`, `pipLine`, `pipBubble`
    and `composer`;
  - `ios/Mivu/Coach/CoachReplyLines.swift` `dayTitle`;
  - `ios/Mivu/Coach/CoachHistoryView.swift` `captureLabel`;
  - `ios/MivuTests/PipLineTests.swift` (copied as Android tests).
- #69 `30b76a3e`: `ios/Mivu/Design/MotionPolicy.swift`.
- #46: `CoachView.swift` `composerHeight`, the composer `.background`
  gradient, and `CoachTimelineView.bottomInset`.
- #45: `CoachView.swift` `openQuote` (`case .workout`).

## Scope decisions

**Kept:** the nine items in the goal, all copying iOS exactly.

**Decided, each with its reason:**
- **No floor marker on Android totals except the Coach day chip.** iOS shows
  "80+" and "at least" only in the Live Activity (#64, #65), which Android
  lacks (`live-activity` is `n/a`), and on the Coach day chip (#67). Today and
  the receipts keep their existing disclosures: "Some nutrients are unknown…"
  and "Some nutrients unknown". The widget shows only kcal and has no floor
  marker on iOS either.
- **`failureReason` text on Android** is the error's class path from its
  sealed parent, for example `CoachError.InvalidArguments`,
  `ResponsesClient.Failure.Http(503)` and `DiaryError.InvalidData`. Any other
  throwable gives its `javaClass.simpleName`, capped at 40 characters. A
  message is never included, so no user text, model output or URL can reach
  it. iOS writes `Mivu.CoachError.invalidArguments` and `NSURLErrorDomain(-1009)`.
  The field is a diagnostic, never parsed, so the spellings may differ
  between the platforms.
- **Logging.** Android logs as iOS does: `Log.w("Coach", …)` with the
  `failureReason` only. The log lines are "Coach batch rejected for
  correction: <reason>", "Coach turn retrying after <reason>", "Coach turn
  failed: <reason>", "Coach turn left unfinished: <reason>" and "Coach worker
  failed: <reason>". The `CoachWorker` doc comment "Nothing is logged"
  changes to "Only failure codes are logged".
- **The failure-state write is no longer swallowed.** The engine's last
  `failCoachTurn` drops its `runCatching`. If that write throws, its error is
  added to the original error as suppressed, and the original is rethrown.
  The worker's settle step then finds the turn still `analyzing` and settles
  it.
- **Settle runs only after `CoachEngine.run` has started.** A `bind()`
  failure (no connection) keeps today's path: the turn stays `captured` and
  waits for the connection. This matches iOS, which settles only engine and
  prepare failures.
- **Pip's recovery adds `needsClarification`.** iOS `companionNeedsRecovery`
  includes `needsClarification`. Android `RECOVERY` lacked it, so Pip's pose
  and the bubble ("I need a bit more detail. My question is above.") now
  follow iOS.
- **"Processing"** for the bubble is iOS `companionIsProcessing`: not in
  recovery, and either sending or the worker's `activity` is on a turn.
- **Pip's typing gaze already follows the caret.** `CoachComposer.Field`'s
  `onTextLayout` passes the last line's right edge over the field width,
  0…60, which is iOS `CompanionContext.caretSignal`. The audit's "draft
  length" refers only to the parameter's name. No change; the parity row says
  so.
- **The share sheet keeps `loggingLine()`.** It is not the Coach composer,
  and iOS Tell Coach has no chip. Only the Coach composer's `logging` flow
  and `Caption` are removed.
- **The connected footnote stays** ("Using ChatGPT plan · Manage usage").
  The not-connected footnote line is removed: the bubble's Connect replaces
  it, as on iOS.
- **The iOS archive fixture direction is unaffected.**
  - `fixtures/archive/ios-v4-full.json` has no `failureReason`, so
    `android-v4-full.json` and `androidExportStillMatchesFixture` are
    unchanged.
  - The new field is covered by a JVM round-trip test.
  - No fixture is regenerated, and no iOS run is needed.

**Deferred or cut:**
- **#49, on-device fallback (Gemini Nano).** It is a separate owner decision.
  ML Kit GenAI/AICore runs on few devices, has no tool calling for Coach, and
  has no Android nutrition table. `coach-on-device` stays `pending`.
- **#50, profile delete.** Android has no profiles screen yet; it belongs
  with porting profiles. `profile-delete` stays `pending`.
- **#72, meal notification "At least N kcal".** Android has no
  meal-analysis notification, so the row is `n/a` until it does. It is
  recorded in carried items so the rule applies when that notification is
  built.
- **Coach timeline day dividers.** They are not in Android today and not in
  this scope. `dayTitle` is used only by Chat history.
- **#47, #53, #57, #61, #62, #65, #68, #73, #74 and #76:** test-only, CI,
  release or Live Activity changes; `n/a`.

## Global Constraints

- **Paths:** `A/` = `android/app/src/main/java/com/yakov103/mivu/`, `T/` =
  `android/app/src/test/java/com/yakov103/mivu/`, `I/` =
  `android/app/src/androidTest/java/com/yakov103/mivu/`.
- **Platform:** minSdk 31, targetSdk 37; no new dependency or permission.
- **Data:**
  - no schema change;
  - `CoachTurn.failureReason: String? = null` is the only model change;
  - the archive stays `mivu-diary` v4, and both fixtures must still pass;
  - a `failureReason` over 200 UTF-8 bytes is `DiaryError.InvalidData`;
  - the next run of the turn clears it.
- **Coach safety** (AGENTS.md "Coach chat history"):
  - a rejected batch runs nothing;
  - the retry never saves twice: receipts make it `replayOnly`;
  - accepted capture identity and context, and committed receipts, are never
    changed;
  - saved food is never reported as a failure.
- **Privacy:** `failureReason` and logs hold only error class names and HTTP
  codes, never prompt, context, reply, token or URL text.
- **Synthetic data only:** meals such as "Synthetic toast" (530 kcal) and
  "two boiled eggs and a slice of toast"; a 2,100 kcal goal; scripted
  inference through `CoachEngineTest.Script` and `CoachWorkerTest`. No live
  ChatGPT call, and no emulator use while writing this plan.
- **Accessibility:**
  - 48 dp targets for Try again, Connect and the chip;
  - the chip's spoken label is iOS `spoken` ("Logging to today, 1,240 of
    2,100 kcal"), with the hint "Opens Today";
  - the bubble is a polite live region;
  - at `isLargeText()` (font scale ≥ 1.3) the greeting (`PipLine.Say`) is
    hidden, while working, problem and connect lines still show;
  - with "Remove animations" on, the spinner is a still icon hidden from
    TalkBack;
  - Pip stays hidden from TalkBack.
- **Copy** (verbatim from iOS `PipLine.swift`, `CoachView.swift` and
  `CoachEngine.swift`):
  - **greetings:**
    - 04–10 "Morning! What’s for breakfast?";
    - 11–14 "Ready for lunch?";
    - 15–17 "What have you had today?";
    - 18–21 "What’s for dinner?";
    - otherwise "Anything to log?";
    - after a logged meal, "Anything else to log?";
  - **working:** "Looking at your photo…" or "Counting that up…";
  - **problems:**
    - "I’m offline. I’ll pick this up when you’re back.";
    - "I need a bit more detail. My question is above.";
    - "That one didn’t go through." (with "Try again");
    - "Something went wrong.";
  - **connect:** "Connect ChatGPT so I can count for you", with the button
    "Connect";
  - **chip:** "<Day> · <eaten>[+] / <goal> kcal", or "<Day> · <eaten> kcal"
    without a goal. An unknown amount reads "—" when meals exist and "0" when
    none do. Spoken: "Logging to <day>, [at least ]<eaten>[ of <goal>] kcal";
  - **the correction output**, exactly:
    `{"saved":false,"error":"<reason>","detail":"This whole batch was rejected and nothing ran. Retry with arguments that match the tool schema and only retrieved IDs, revisions and evidence; call ask_clarification alone; or answer without claiming a save."}`;
  - **history:** the row title is `dayTitle` ("Today", "Yesterday", "Oct 17",
    "Oct 17, 2025"). The time is short ("8:12 AM"); " · <zone short name>"
    is added only when the row's zone differs from the phone's.
- **Speed:**
  - each task runs only its own test classes, one class per
    `connectedDebugAndroidTest` run;
  - the full suite runs once, in Task 6;
  - batch review 1 runs after Task 3, batch review 2 after Task 5, and the
    final review after Task 6.

  ```sh
  cd android
  ./gradlew :app:testDebugUnitTest --tests '*<Class>'
  ./gradlew :app:connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=com.yakov103.mivu.<pkg>.<Class>
  ```

## Review Focus

1. **A write batch with one bad call, followed by a corrected batch.**
   Nothing from the first batch is committed. The model receives
   `"saved":false` for every call in that batch. The corrected batch commits
   exactly one receipt.
   (Task 2: `rejectedCallIsReturnedToModelToCorrect`)
2. **A save, then a malformed reply, then the silent retry.** The turn never
   shows `needsRetry` in between and ends with one receipt. A second
   malformed reply fails the turn with `failureReason`, and `LimitExceeded`
   is never retried.
   (Task 2: `retryAfterASavedWriteKeepsOneReceipt`,
   `onlyModelOutputFailuresRetryAndOnlyOnce`)
3. **A turn left `analyzing` after the engine throws.** With saved food it
   becomes `completed` + `incomplete` with the committed summary. Without
   saved food it becomes `needsRetry` with a `failureReason`, and the bubble
   offers Try again.
   (Task 3: `unrecordedFailureAfterSavedFoodEndsWithItsSummary`,
   `unrecordedFailureWithoutSavedFoodOffersTryAgain`,
   `workerSettlesATurnLeftAnalyzing`)
4. **An iOS archive whose turn has a `failureReason`, imported and exported
   on Android.** The field is byte-equal after export. A 201-byte reason is
   refused as invalid data.
   (Task 2: `failureReasonSurvivesReexport`, `oversizedFailureReasonIsInvalid`)
5. **A day with one calories-only food ("Synthetic extra", 200 kcal).**
   Protein, carbs and fat show the other foods' sums, "Some nutrients are
   unknown…" stays on Today. When a saved food lacks kcal, the Coach chip
   marks the figure as a floor ("400+", spoken "at least 400").
   (Task 1: `unknownComponentsAddNothingAndAreCounted`; Task 4:
   `foodWithoutCaloriesMakesTheChipALowerBound`)

---

### Task 1: Known nutrient values add up (#64)

**Files:**
- Modify:
  - `A/diary/DiaryMath.kt:24-25` (`sumOrNull`);
  - `A/ui/coach/CoachReceiptPresentation.kt:109-113` (`committedTotal`).
- Test:
  - `T/diary/DiaryMathTest.kt`;
  - `T/ui/coach/CoachReceiptPresentationTest.kt`;
  - also any class `rg -l "Protein unknown|protein.*null"` lists:
    `T/progress/ProgressInsightsTest.kt`, `T/coach/CoachToolsTest.kt`,
    `I/coach/CoachEngineTest.kt` and `I/diary/MealEditsTest.kt`. Update
    their assertions only where they assume the old rule.

**Interfaces:**
- Produces: the unchanged signatures of `nutritionTotals`,
  `dayNutritionTotals` and `dailyProgress`, with the new rule. Task 4's chip
  reads `dayNutritionTotals(...).kcal`.

- [ ] **Step 1: Failing tests.**
  - `DiaryMathTest`:
    - rename `oneMissingMacroMakesThatTotalNull` to
      `unknownComponentsAddNothingAndAreCounted`. Items
      `A(kcal 10, carbs 1, protein null, fat 0)` and
      `B(20, 2, 3, 4)` give kcal 30 and protein 3, with `unknownItemCount`
      1. `nutritionTotals(listOf(A)).protein` is null, and
      `nutritionTotals(emptyList()).kcal` is null;
    - `dailyAddsKnownSubtotals`: two subtotals, one with protein 5 and one
      with null, give protein 5 and `unknownItemCount` the sum.
  - `CoachReceiptPresentationTest.committedMacrosAddOnlyKnownValues`, the
    iOS sequence:
    - items (100, 0, 10.5, 2) and (50, 0, 4.5, 3), then the second item's
      protein set to null: "150 kcal" and "Carbs 0 g · Protein 10.5 g · Fat
      5 g", with "Some nutrients unknown";
    - the first item's nutrition null: "50 kcal" and "Carbs 0 g · Protein
      unknown · Fat 3 g";
    - both null: "Energy unknown" and "Carbs unknown · Protein unknown · Fat
      unknown".
- [ ] **Step 2: Run** both classes. Expected: FAIL on the new assertions.
- [ ] **Step 3: Implement.**
  - `sumOrNull(values) = values.filterNotNull().takeIf { it.isNotEmpty() }?.sum()`,
    with the iOS doc line "Each nutrient adds the items that know it and is
    nil only when none do; unknownItemCount discloses the gap."
  - `committedTotal` gets the same body over
    `receipt.items.mapNotNull { it.nutrition?.let(nutrient) }`.
- [ ] **Step 4: Run** `DiaryMathTest`, `CoachReceiptPresentationTest`,
  `ProgressInsightsTest`, `CoachToolsTest`, `WidgetSnapshotTest`, then `CoachEngineTest` and `MealEditsTest`. Expected: PASS after
  updating only the old-rule assertions.
- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/java/com/yakov103/mivu/diary/DiaryMath.kt android/app/src/main/java/com/yakov103/mivu/ui/coach/CoachReceiptPresentation.kt android/app/src/test android/app/src/androidTest
git commit -m "fix(android): add known nutrient values when some foods lack them"
```

### Task 2: Coach correction loop, silent retry and `failureReason` (#66 and archive round trip)

**Files:**
- Modify:
  - `A/diary/CoachModels.kt` (`CoachTurn.failureReason`, the last
    property);
  - `A/diary/DiaryDatabase.kt:296` (`updateCoachTurn(..., failureReason: String? = null)`
    sets it);
  - `A/diary/DiaryCapture.kt:87` (`failCoachTurn(..., failureReason: String? = null)`);
  - `A/diary/DiaryValidation.kt:164-171` (`validateTurn`: at most 200 UTF-8
    bytes);
  - `A/coach/CoachEngine.kt` (`run`, `attempt`, the correction catch and the
    companion helpers).
- Test:
  - `I/coach/CoachEngineTest.kt`;
  - `T/coach/CoachFailureReasonTest.kt` (new, JVM);
  - `T/diary/DiaryArchiveTest.kt`.

**Interfaces:**
- Produces, in `CoachEngine.Companion`:
  - `fun failureReason(error: Throwable): String`:
    - for `CoachError`, `DiaryError`, `SessionError` and
      `ResponsesClient.Failure` it is
      `error.javaClass.name.substringAfterLast('.').replace('$', '.')`, plus
      `"(<code>)"` for `Failure.Http`;
    - otherwise `error.javaClass.simpleName.take(40)`;
  - `fun isCorrectable(error: Throwable): Boolean`: `CoachError.InvalidTool`,
    `CoachError.InvalidArguments`, `is DiaryError.InvalidData`,
    `DiaryError.NotFound`, `DiaryError.StaleRevision` and
    `DiaryError.InvalidAmountUnitChange`;
  - `fun isModelOutputFailure(error: Throwable): Boolean`:
    `CoachError.InvalidTool`, `CoachError.InvalidArguments`,
    `is ResponsesClient.Failure.Malformed` and `Failure.ResponseFailed`.
    `LimitExceeded` is excluded.
- Produces: `DiaryDatabase.Tx.failCoachTurn(turnID, state, needsDayChoice = false, failureReason: String? = null)`,
  which Task 3 uses.

- [ ] **Step 1: Failing tests.**
  - `CoachFailureReasonTest` (JVM):
    - `CoachError.InvalidArguments` gives "CoachError.InvalidArguments";
    - `ResponsesClient.Failure.Http(503)` gives
      "ResponsesClient.Failure.Http(503)";
    - `DiaryError.InvalidData("coach json")` gives "DiaryError.InvalidData",
      without the reason;
    - `java.net.SocketTimeoutException("secret")` gives
      "SocketTimeoutException";
    - every result is at most 200 bytes;
    - the `isCorrectable` and `isModelOutputFailure` tables are pinned;
      `LimitExceeded`, `AmbiguousDay` and `Unauthorized` are false for both.
  - `CoachEngineTest`, porting the iOS tests:
    - `rejectedCallIsReturnedToModelToCorrect`: round 1 is
      `log_food` with a fabricated meal ID plus a valid call. There are no
      receipts afterwards. The round-2 input holds both calls'
      `FunctionOutput`s, each starting `{"saved":false,"error":"`. Round 2
      saves "Synthetic toast" and round 3 answers. The result has exactly
      one receipt and is `completed`.
    - `modelOutputFailureRetriesOnceWithoutShowingIt`: the first reply
      throws `Failure.Malformed("x")`, and the script records `stored(id).state`
      on every call. State is `analyzing` at the retry's first call, and the
      turn completes.
    - `onlyModelOutputFailuresRetryAndOnlyOnce`:
      - two malformed replies give `needsRetry`, with `failureReason`
        "ResponsesClient.Failure.Malformed", after 2 inference calls;
      - `CoachError.LimitExceeded` (nine rounds of reads) is not retried;
      - `Failure.Unauthorized` gives one call and `waitingForConnection`.
    - `retryAfterASavedWriteKeepsOneReceipt`: a save, then a malformed
      reply, then the retry in `replayOnly` answers. The turn has one
      receipt and is `completed`.
    - `failedTurnKeepsOnlyItsFailureCode`: `Failure.Http(503)` gives
      `failureReason == "ResponsesClient.Failure.Http(503)"`. A later
      successful run clears it to null.
    - Existing tests that expected a rejected batch to fail the turn
      (`clarificationMustBeOnlyCall` and any `InvalidArguments` case) now
      expect the model to be told. Then either the script runs out
      (`LimitExceeded`, `needsRetry`) or the turn completes without
      receipts. Their checks that nothing stale or duplicate is committed
      stay.
  - `DiaryArchiveTest`:
    - `failureReasonSurvivesReexport`: decode `ios-v4-full.json`, copy one
      turn with `failureReason = "CoachError.InvalidArguments"`, encode,
      decode, encode again. The field is equal, and the two encodings are
      byte-equal.
    - `oversizedFailureReasonIsInvalid`: 201 ASCII bytes gives
      `DiaryError.InvalidData`.
- [ ] **Step 2: Run** `CoachFailureReasonTest`, `DiaryArchiveTest` and
  `CoachEngineTest`. Expected: FAIL (no `failureReason`; the rejected batch
  fails the turn; no retry).
- [ ] **Step 3: Implement**, in iOS order:
  - `run(turnID)` calls `attempt(turnID, isFinal = false)`, catching
    `isModelOutputFailure`. It logs "Coach turn retrying after <reason>" and
    returns `attempt(turnID, isFinal = true)`.
  - In `attempt`'s catch, before the saved-food check:
    `if (!isFinal && isModelOutputFailure(error)) throw error`. It then logs
    "Coach turn failed: <reason>" and passes `failureReason = reason` to
    `failCoachTurn`.
  - In `rounds`, one `try` wraps:
    - the `parse` map;
    - `writes`;
    - the clarification lookup with its "only call" check;
    - the duplicate-target check;
    - `validateCoachWrites`, only when there is no clarification.

    A `catch` where `isCorrectable(e)`:
    - logs "Coach batch rejected for correction: <reason>";
    - appends `PriorOutput` for each `outputItems` entry, then one
      `FunctionOutput(callID, output)` per call;
    - throws `LimitExceeded` when `input.size > 128`;
    - continues with `return@repeat`.

    Clarification handling moves after the `try`, unchanged.
  - The callID uniqueness check stays outside the `try`. It is a model-output
    failure that is retried, not corrected, as on iOS.
- [ ] **Step 4: Run** the three classes, then `CoachJobServiceTest` and
  `ArchiveRoundTripTest` (the golden fixture must be unchanged). Expected:
  PASS.
- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/java/com/yakov103/mivu/coach/CoachEngine.kt android/app/src/main/java/com/yakov103/mivu/diary android/app/src/test/java/com/yakov103/mivu/coach/CoachFailureReasonTest.kt android/app/src/test/java/com/yakov103/mivu/diary/DiaryArchiveTest.kt android/app/src/androidTest/java/com/yakov103/mivu/coach/CoachEngineTest.kt
git commit -m "fix(android): let the model correct rejected tool calls and retry failed replies once"
```

### Task 3: Never leave a failed turn on Thinking (#71)

**Files:**
- Modify:
  - `A/coach/CoachEngine.kt` (`attempt`: the `analyzing` write goes inside
    `try`; the last `failCoachTurn` is not swallowed);
  - `A/coach/CoachWorker.kt` (`pass` settles; the doc comment);
  - `A/diary/DiaryCapture.kt` (`settleCoachTurn`).
- Test: `I/coach/CoachWorkerTest.kt`.

**Interfaces:**
- Consumes: `CoachEngine.failureReason`, and `failCoachTurn(..., failureReason)`
  (Task 2).
- Produces: `fun DiaryDatabase.settleCoachTurn(turnID: UUID, error: Throwable)`.
  It reads the turn without photos and returns when the state is not
  `captured` or `analyzing`:
  - with receipts, `finishCoachTurn(turnID, coachCommittedSummary(turnID), incomplete = true)`;
  - if that fails or there are no receipts, `failCoachTurn(turnID, needsRetry, failureReason = CoachEngine.failureReason(error))`,
    after logging "Coach turn left unfinished: <reason>".

  Each write is its own transaction; a failure of the summary path falls
  through to `needsRetry`. This is iOS `settle`.

- [ ] **Step 1: Failing tests** in `CoachWorkerTest`:
  - `unrecordedFailureAfterSavedFoodEndsWithItsSummary`:
    - a scripted engine run saves "Synthetic toast" (530 kcal) and
      completes;
    - `tx.failCoachTurn(id, analyzing)` simulates the lost failure write;
    - `db.settleCoachTurn(id, IOException())`;
    - the result is `completed`, `incomplete == true`, `assistantText` not
      null, and one receipt.
  - `unrecordedFailureWithoutSavedFoodOffersTryAgain`: a captured turn set to
    `analyzing`, then `settleCoachTurn`, gives `needsRetry` and
    `failureReason == "IOException"`.
  - `settleLeavesAFinishedTurnAlone`: a `completed` turn and a
    `waitingForNetwork` turn are unchanged.
  - `workerSettlesATurnLeftAnalyzing`: `CoachWorker` gains a constructor
    parameter
    `settle: (DiaryDatabase, UUID, Throwable) -> Unit = DiaryDatabase::settleCoachTurn`.
    - A spy is passed in, and the inference throws `Failure.Http(500)`.
    - The spy is called once, with that turn's ID, after `run` throws.
    - A `bind()` that throws `CoachError.ConnectionRequired` never calls it.
    - Android has no selection epoch, so the engine's own failure write
      cannot be made to fail without a production hook. The two tests above
      cover what `settleCoachTurn` does.
- [ ] **Step 2: Run** `CoachWorkerTest`. Expected: FAIL (no
  `settleCoachTurn`).
- [ ] **Step 3: Implement.**
  - **Engine.**
    - `db.transaction(null) { it.failCoachTurn(turnID, analyzing) }` moves to
      the first line inside `try`.
    - The final state write becomes
      `try { db.transaction(null) { … } } catch (w: Exception) { error.addSuppressed(w) }`,
      then `throw error`.
  - **Worker.**
    - In `pass`, set `started = true` immediately before `.run(turnID)`.
    - In the `catch (e: Exception)` that ends the pass, when `started`, call
      `settle(db, turnID, e)` inside `runCatching`, so a settle failure
      still ends the pass quietly.
    - The outer catch logs "Coach worker failed: <reason>".
- [ ] **Step 4: Run** `CoachWorkerTest`, `CoachEngineTest` and
  `CoachJobServiceTest`. Expected: PASS.
- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/java/com/yakov103/mivu/coach android/app/src/main/java/com/yakov103/mivu/diary/DiaryCapture.kt android/app/src/androidTest/java/com/yakov103/mivu/coach/CoachWorkerTest.kt
git commit -m "fix(android): never leave a failed Coach turn stuck on Thinking"
```

**Batch review 1** (Tasks 1–3) runs here: Ponytail Review of the diff
against the iOS diffs `2ed34e43`, `75173ccb` and `f0c78a4c`.

### Task 4: Pip's bubble and the day intake chip across the composer (#67, #70)

**Files:**
- Create:
  - `A/ui/coach/PipLine.kt` (`PipLine`, `CoachDayChip` and `coachDayChip`).
- Modify:
  - `A/ui/coach/CoachViewModel.kt`:
    - `coachDay` replaces the composer's `logging`;
    - add `pip`;
    - `RECOVERY` gains `needsClarification`;
    - add `sentWithPhotos`;
  - `A/ui/coach/CoachComposer.kt`:
    - the strip with the bubble and chip sits above a `Row` of field and
      button;
    - remove `Caption`;
    - remove `Footnote`'s not-connected branch;
  - `A/ui/coach/CoachScreen.kt` and `A/ui/MivuApp.kt` (`onSeeToday` reaches
    the chip).
- Test:
  - `T/ui/coach/PipLineTest.kt` (new);
  - `I/ui/coach/CoachComposerTest.kt`.

**Interfaces:**
- Consumes: `dayNutritionTotals` (Task 1) and `CoachReplyLines.dayLabel`.
- Produces:
  - `sealed interface PipLine { data class Say(val text: String); data class Working(val text: String); data class Problem(val text: String, val detail: String?, val canRetry: Boolean); data object Connect }`,
    with
    `companion fun current(hour: Int, mealsLogged: Boolean, typing: Boolean, connected: Boolean, processing: Boolean, withPhotos: Boolean, recovery: Boolean, error: String?, turnState: CoachTurnState?): PipLine?`.
    The branch order is iOS `PipLine.current`.
  - `data class CoachDayChip(val text: String, val spoken: String)` and
    `fun coachDayChip(localDate: String, today: String, kcal: Double?, kcalPartial: Boolean, mealsLogged: Boolean, goal: Double?): CoachDayChip`:
    - the day is `dayLabel(...)` with its first character in title case;
    - numbers use `NumberFormat.getIntegerInstance()`, as iOS
      `.fractionLength(0)` does.
  - `data class CoachDay(val chip: CoachDayChip, val mealsLogged: Boolean)` and
    `internal fun DiaryDatabase.coachDay(): CoachDay?`, null without an
    active day:
    - `kcal` is `dayNutritionTotals(meals, complete).kcal`;
    - `kcalPartial` is true when any saved meal's item has `kcal == null`;
    - `mealsLogged` is `meals.isNotEmpty()`;
    - `goal` is `goalOn(day.localDate, goals)?.targets?.kcal`;
    - `today` is `LocalDate.now(profile zone)`.
  - `data class PipState(val processing: Boolean, val withPhotos: Boolean, val recovery: Boolean, val turnID: UUID?, val turnState: CoachTurnState?)`
    and `val CoachViewModel.pip: StateFlow<PipState>`, set in
    `resolveCompanion`:
    - `recovery` is `message != null || latest in RECOVERY`;
    - `processing` is `!recovery && (sending || activity != null)`;
    - `sentWithPhotos` is set by `send()` when the draft had photos, and
      reset when `processing` ends (iOS `shortcut:` copied with its limit).
  - `val CoachViewModel.coachDay: StateFlow<CoachDay?>`, read after every
    `repository.changes`.

- [ ] **Step 1: Failing tests.**
  - `PipLineTest`: port the six `PipLineTests` exactly, with every
    expectation string as in `ios/MivuTests/PipLineTests.swift`:
    - `idleFollowsTheTimeOfDayUntilSomethingIsLogged`;
    - `typingHidesOnlyTheIdleLine`;
    - `workingNamesTheInput`;
    - `recoveryKeepsTheDetailAndOffersRetryOnlyWhenItApplies`;
    - `chipNamesTheLoggingDayAndIntake`, which includes "Today · 1,240 /
      2,000 kcal", "Logging to today, 1,240 of 2,000 kcal", "Yesterday ·
      1,240 kcal" and "Today · — / 2,000 kcal";
    - `foodWithoutCaloriesMakesTheChipALowerBound`, with "Today · 400+ /
      2,000 kcal" and "Logging to today, at least 400 of 2,000 kcal".

    Run it under `Locale.US`.
  - `CoachComposerTest`:
    - `idleBubbleGreetsAndChipOpensToday`: a fixed fixture hour isn't
      injectable, so assert the `coachPipLine` node exists with one of the
      five greetings. The `coachDate` chip text is "Today · 0 / 2,100 kcal",
      its content description is the spoken line, it is ≥ 48 dp tall, and a
      click calls `onSeeToday`.
    - `bubbleSpansTheComposerWidth`: the bubble's right edge passes the left
      edge of the round button (#70). On a 360 dp-wide window, "Today ·
      1,935 / 2,100 kcal" is one line (text layout `lineCount == 1`).
    - `typingHidesTheGreeting`.
    - `needsRetryBubbleOffersTryAgain`: a `needsRetry` turn shows "That one
      didn’t go through." and the detail line. Try again (48 dp) calls
      `retry`, and it is disabled while `activity != null`.
    - `largeFontHidesOnlyTheGreeting`: at font scale 2.0 there is no `Say`
      text, while a `needsRetry` turn still shows its line.
    - Replace `notConnectedFootnoteOffersConnect` and
      `connectLinkAsksConsentFirst` with `notConnectedBubbleOffersConnect`
      and `bubbleConnectAsksConsentFirst`. "Messages save on this phone." no
      longer exists. `connectedFootnoteShowsManageUsage` is unchanged.
- [ ] **Step 2: Run** `PipLineTest` and `CoachComposerTest`. Expected: FAIL.
- [ ] **Step 3: Implement**, following iOS `companionStrip` and `pipBubble`
  and mockup frames 1–4:
  - **Structure.** A `Column` of the strip, then a `Row` of the field and
    the round button. The strip is a `Row(Bottom)`: `CoachPip`, then a
    `Column(weight 1f)` with the bubble over the chip.
  - **Bubble.**
    - `Surface` color `surface`, with a 0.5 dp `outlineVariant` border at
      50% alpha;
    - shape `RoundedCornerShape(18.dp, 18.dp, 18.dp, 6.dp)`, with
      bottom-start 6 dp;
    - padding 14 by 10 dp, text `bodyMedium`;
    - the detail is `bodySmall` in `onSurfaceVariant`;
    - Try again and Connect are `TextButton`s in `labelLarge` SemiBold,
      48 dp tall;
    - Connect is `ChatGPTConnectButton(connection, onAgree, onConnect, title = "Connect", style = ConnectStyle.Link)`;
    - the problem text carries the `coachError` tag.
  - **Chip.**
    - `Surface(onClick = onSeeToday)`, a capsule in
      `MivuTheme.colors.summarySurface`;
    - text `labelMedium` with `.tabular()` in `primary`, padding 12 by 6 dp;
    - `heightIn(min = 48.dp)` through the click area;
    - tag `coachDate`, `contentDescription = chip.spoken`, and
      `onClickLabel = "Opens Today"`.
  - **Animations.** The spinner is a 16 dp `CircularProgressIndicator`. With
    the animator scale at 0 it is the still, determinate overload
    (`progress = { 0.75f }`), cleared from semantics. This is the Android form
    of iOS's static `circle.dotted`, and it needs no new drawable.
  - **Weigh-in bubble.** The morning weigh-in `bubble` slot stays above the
    strip, unchanged.
- [ ] **Step 4: Run** `PipLineTest`, `CoachComposerTest` and
  `CoachScreenTest`. Expected: PASS.
- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/java/com/yakov103/mivu/ui android/app/src/test/java/com/yakov103/mivu/ui/coach/PipLineTest.kt android/app/src/androidTest/java/com/yakov103/mivu/ui/coach/CoachComposerTest.kt
git commit -m "feat(android): Pip speaks in a bubble with a day intake chip"
```

### Task 5: Chat behind the composer, history rows, workout quotes and motion (#46, #67, #45, #69)

**Files:**
- Modify:
  - `A/ui/coach/CoachScreen.kt`:
    - the `Column` becomes a `Box`;
    - the composer overlays the timeline, with the fade;
    - `openQuote` opens a workout;
    - add `onOpenWorkout`;
  - `A/ui/MivuApp.kt` (`onOpenWorkout = { navController.navigate(Route.WorkoutDetail(it.toString())) }`);
  - `A/ui/coach/CoachComposer.kt` (the composer background);
  - `A/coach/CoachReplyLines.kt` (`dayTitle`);
  - `A/ui/coach/CoachHistoryScreen.kt` (row titles, `captureLabel`,
    "Selected date", the filtered empty line);
  - `A/pip/MotionPolicy.kt` (drop `powerSave` and its receiver).
- Test:
  - `T/pip/MotionPolicyTest.kt`;
  - `T/coach/CoachReplyLinesTest.kt` (new);
  - `I/ui/coach/CoachScreenTest.kt`;
  - `I/ui/coach/CoachHistoryScreenTest.kt`.

**Interfaces:**
- Produces:
  - `fun CoachReplyLines.dayTitle(localDate: String, zone: String): String`,
    which is
    `dayLabel(localDate, LocalDate.now(ZoneId.of(zone)).toString()).replaceFirstChar { it.titlecase(Locale.getDefault()) }`;
  - `MotionPolicy.playback(removeAnimations: Boolean, thermalStatus: Int, resumed: Boolean, covered: Boolean = false)`;
  - `CoachScreen(..., onOpenWorkout: (UUID) -> Unit = {})`.

- [ ] **Step 1: Failing tests.**
  - `MotionPolicyTest`:
    - remove `powerSaveIsStatic` and the `saver` parameter;
    - keep `removeAnimationsIsStatic`, `severeThermalIsStatic` (moderate
      animated; severe and shutdown static), `notResumedIsHidden`,
      `coveredIsHidden` and `otherwiseAnimated`. This is iOS #69 exactly:
      only Reduce Motion and serious heat hold Pip.
  - `CoachReplyLinesTest.dayTitleIsRelativeToTheProfileZone`: today's date
    in "Pacific/Kiritimati" gives "Today", the day before gives "Yesterday",
    "2025-10-17" gives "Oct 17, 2025", and a garbage date passes through.
  - `CoachHistoryScreenTest.listsNewestFirstWithCaptureLabel`: the London row
    (08:12:05 BST) shows "Oct 24" (or "Today" when the fixture date is
    today) and "8:12 AM · <London short name>" under a non-London default
    zone. A row in the default zone shows only "8:12 AM". Set
    `TimeZone.setDefault` and `Locale.US` in `@Before`, restored in
    `@After`.
  - `CoachScreenTest`:
    - `timelineScrollsBehindTheComposer`:
      - the newest row's bottom sits above the composer's top at the
        latest position;
      - a swipe that starts in the faded band (8 dp above the field, left
        of Pip) scrolls the timeline;
      - Jump to latest and the later-edge control sit above the composer;
    - `jumpToLatestIs48dpWithSpokenLabel` and
      `dragOnJumpToLatestScrollsTimeline` still pass (AGENTS.md);
    - `workoutQuoteOpensTheWorkout`: a sent turn quoting a workout, when its
      quote is tapped, calls `onOpenWorkout` with the workout ID.
- [ ] **Step 2: Run** the four classes. Expected: FAIL.
- [ ] **Step 3: Implement.**
  - **#46.**
    - `Box(Modifier.fillMaxSize())`: the timeline box fills it, and
      `CoachComposer` is aligned to `BottomCenter` and reports its height
      through `onSizeChanged`.
    - The `LazyColumn` gets `contentPadding(bottom = composerHeight + 8.dp)`.
    - `JumpToLatest`, the later `Edge` and the `SnackbarHost` get
      `padding(bottom = composerHeight)`. The composer keeps `imePadding`,
      so its height includes the keyboard.
    - Composer background, as iOS: `drawBehind` with
      `Brush.verticalGradient(0f to background.copy(alpha = 0f), 56.dp.toPx() / size.height to background)`.
      There is no pointer input on the background, so drags in the
      transparent band reach the list.
    - Remove the CoachScreen header comment "The composer and Pip dock below
      the timeline box".
  - **#45.** `is CoachReply.Target.Workout -> onOpenWorkout(target.workoutID)`,
    and remove the `shortcut:` comment at `CoachScreen.kt:215`.
  - **#67 history.**
    - Rows, "Selected date" and the "No saved conversation is labeled …"
      line use `dayTitle(date, zone.id)`.
    - `captureLabel` is
      `DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).withZone(rowZone).format(firstCapturedAt)`.
      When `rowZone.normalized() != ZoneId.systemDefault().normalized()`,
      append `" · " + rowZone.getDisplayName(TextStyle.SHORT, Locale.getDefault())`.
    - The KDoc is updated to the new example.
  - **#69.** Drop `powerSave`, `saver`, its `registerReceiver` and
    `unregisterReceiver`, and the `ACTION_POWER_SAVE_MODE_CHANGED` import.
    Update the KDoc to "still under Remove animations or severe heat;
    Power Saver keeps Pip moving, as iOS Low Power Mode". The thermal
    listener stays registered while composed, so iOS's re-read on activation
    has no Android counterpart.
- [ ] **Step 4: Run** `MotionPolicyTest`, `CoachReplyLinesTest`,
  `CompanionPresentationTest`, `CoachScreenTest`, `CoachHistoryScreenTest`
  and `CoachComposerTest`. Expected: PASS.
- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/java/com/yakov103/mivu android/app/src/test/java/com/yakov103/mivu/pip/MotionPolicyTest.kt android/app/src/test/java/com/yakov103/mivu/coach/CoachReplyLinesTest.kt android/app/src/androidTest/java/com/yakov103/mivu/ui/coach
git commit -m "feat(android): float the Coach composer over the chat and match iOS history, quotes and motion"
```

**Batch review 2** (Tasks 4–5) runs here. Compare the screenshots from
Task 6 Step 2 with the mockup and with `ios-coach-pip-reference.png`.

### Task 6: Full suite, evidence and parity

**Files:**
- Create:
  - `docs/verification/2026-10-26-android-ios-catchup.md`;
  - `docs/verification/android-catchup/*.png`.
- Modify:
  - `docs/parity.md`;
  - `docs/superpowers/plans/android-carried-items.md`.

- [ ] **Step 1: Run the full suite once** at a clean commit:
  `./gradlew :app:testDebugUnitTest :app:connectedDebugAndroidTest :app:lintDebug :app:assembleRelease --rerun-tasks`,
  then `python3 scripts/ci/parity.py` and the `scripts/ci` unit tests.
  - Record the SHA, the emulator, and the counts from the JUnit XML.
  - Never count a skipped or zero-test class.
  - Record a failing class honestly, with its cause.
- [ ] **Step 2: Screenshots** in light, dark and font scale 2.0, compared
  with the mockup:
  - `coach-idle`;
  - `coach-working-partial` (a calories-only food, so the chip reads "+");
  - `coach-needs-retry`;
  - `coach-not-connected`;
  - `coach-scrolled-behind`;
  - `history-rows`;
  - `today-partial-macros` (protein shown with the unknown disclosure).

  Power Saver motion and thermal are `blocked` on the emulator, the same as
  iOS's simulator note; record them for a physical phone.
- [ ] **Step 3: Parity** (`docs/parity.md`). Mark a row Android `done` only
  where every named test passed.
  - New `post-baseline` rows. iOS is `partial` where a PR has no
    verification record; name the PR in the notes.
    - `auto-closed-days` (#58): Android `done`, [DayStatusTest, DiaryDaysTest]
      plus the existing Skip/Count records;
    - `coach-reply-lines` (#59): Android `done`, [CoachReplyCheckTest,
      CoachReplyTextTest, CoachScreenTest];
    - `nutrient-known-totals` (#64): [DiaryMathTest,
      CoachReceiptPresentationTest];
    - `coach-correction` (#66): [CoachEngineTest, CoachFailureReasonTest,
      DiaryArchiveTest];
    - `pip-bubble` (#67, #70): [PipLineTest, CoachComposerTest,
      CoachHistoryScreenTest];
    - `pip-low-power` (#69): Android `done` [MotionPolicyTest], with
      physical-phone Power Saver `blocked`;
    - `coach-stuck-turns` (#71): [CoachWorkerTest];
    - `meal-notification-floor` (#72): Android `n/a`, with the note "until
      Android has a meal-analysis notification; carried";
    - `setup-waking-day` (#75): Android `done` (`fd4fd306`, the existing
      onboarding record).
  - Fixes:
    - `coach-floating-composer`:
      - replace the false "the composer floats over the timeline" note with
        the Task 5 behaviour and tests;
      - the note says Pip's gaze follows the caret through the last line's
        end, as iOS `caretSignal` does;
      - status `done` only if `timelineScrollsBehindTheComposer` passed;
    - `pip`: the note adds that Power Saver no longer stills Pip (#69). It
      was wrongly `done` while the policy differed; keep `done` only if
      `MotionPolicyTest` passed;
    - `progress`: the note says mixed-completeness days now add known values
      (#64). Re-mark `done` only with `ProgressInsightsTest` passing, else
      `partial`;
    - `pip-entry-points`: the note says a workout quote opens the workout
      (#45).
- [ ] **Step 4: Carried items.**
  - Add under "Later": "Meal-analysis notification: apply iOS #72 'At least
    N kcal' with the #64 rule when it is built".
  - Add under "Physical phone (owner)": "Power Saver keeps Pip moving (#69)".
  - Record #49 and #50 as owner decisions, with the reasons in this plan's
    "Deferred".
- [ ] **Step 5: Commit**

```bash
git add docs/verification/2026-10-26-android-ios-catchup.md docs/verification/android-catchup docs/parity.md docs/superpowers/plans/android-carried-items.md
git commit -m "docs(android): record the iOS 1.1.1 catch-up"
```

**Final review** of the whole milestone runs here (Ponytail Review), before
the PR.
