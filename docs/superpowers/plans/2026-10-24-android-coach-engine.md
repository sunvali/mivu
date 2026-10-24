# Android Coach Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port the Coach brain to Android with no UI. A saved Coach turn goes
through bounded context, model rounds with Mivu's tools, and validated writes
with receipts and undo, then finishes as a completed, clarification or
retryable turn. It must match iOS behaviour. Tests run with scripted (fake)
inference, and a debug hook runs it live.

**Architecture:** This is milestone 4a. 4b is the Coach timeline, composer,
camera and voice. 4c is receipts, undo UI, clarification chips, reply and
history.

The engine is ported one to one from iOS:
- `CoachEngine.swift`, `CoachTools.swift`, `CoachManualEdits.swift`,
  `CoachReplyCheck.swift`, `CoachReplyLines.swift` and
  `CoachWriteFingerprint.swift`;
- `DiaryDatabaseCoachMutations.swift` and `DiaryDatabaseCoachContext.swift`;
- `Analysis/CoachInference.swift` and the tool and streaming parts of
  `ResponsesClient.swift`.

Inference is a function value, so tests use a fake. Production uses
`ResponsesClient.respond` with the ChatGPT session from milestone 1. Code
lives in `com.yakov103.mivu.coach`, with storage in
`com.yakov103.mivu.diary`.

**Tech Stack:** Kotlin, coroutines, kotlinx.serialization (`SwiftJson` for
stored data, `JsonElement` for tool schemas and arguments), the platform
SQLite store, JUnit and instrumented tests.

**Spec:** [`docs/superpowers/specs/2026-10-23-android-app-design.md`](../specs/2026-10-23-android-app-design.md),
[`docs/development/coach-chat-behavior.md`](../../development/coach-chat-behavior.md),
[`docs/development/coach-edit-parity.md`](../../development/coach-edit-parity.md),
and the AGENTS.md "Coach chat history" rules. Carried items come from
[`android-carried-items.md`](android-carried-items.md) (milestone 4).

## Global Constraints

- iOS is the authority for every limit, string, tool name, schema, error
  mapping and state transition. That means this checkout's `ios/` code.
  - Engine limits:
    - at most 8 rounds;
    - at most 16 tool calls;
    - at most 128 input items;
    - at most 30 images and 4 MiB per turn;
    - text chunks of 60,000 bytes and 8 images per user message.
  - Tool argument limits:
    - arguments at most 65,536 bytes;
    - strings at most 500 bytes;
    - at most 200 food items;
    - at most 4 clarification candidates.
  - Context limits:
    - 14 days, 40 meals and 24,000 bytes of meals;
    - 60,000 bytes in total;
    - 12 recent turns, at most 1 KB each and 8 KB in total.
- The tool namespace is `mivu` and every tool has `strict: true`. There are
  14 core tools and 18 manual tools, each with the iOS name and schema.
  Unknown or extra keys are rejected.
- `operationKey` is `"<turnID>/<write.target>"`. Replay is idempotent:
  - a turn that already has receipts runs in `replayOnly` mode and sends no
    photos;
  - `commandFingerprint` is stored;
  - `coach_undo` snapshots are gated on the after-state fingerprint.
- `CoachReplyCheck`: the model's text is shown only when every number in it
  is grounded. Otherwise the app writes the sentence from the receipts or
  facts.
- Error mapping and the user-facing strings come from iOS
  `CoachViewModel.message(for:)` and `CoachEngine` failure mapping, with
  "iPhone" replaced by "phone".
- Carried from milestone 3: normalize `CoachSubmissionPayload` attachment
  and context instants with `.stored` before comparing manifests, and add a
  sub-second retry test.
- Never log tokens, prompts with user data, or model output. Tests use
  synthetic data only.
- Every write goes through `transaction(expectedRevision)`. Validate the
  whole batch first, then write once.
- Analysis stays separate from meal calculations, as AGENTS.md requires.

## Review Focus

1. **A tool call with an unknown key, a wrong type or an oversized
   string**: the call is rejected and fed back to the model as iOS does.
   Nothing is written. (Task 3)
2. **A turn re-run after a crash, with receipts already written**: replay
   mode, no duplicate writes, no photos re-sent. (Task 5)
3. **The model claims "saved" with no receipt**: the claim is rejected as
   ungrounded and the turn goes to clarification. (Task 5)
4. **Undo after a later edit to the same meal**: undo is refused because
   the after-state fingerprint differs. (Task 4)
5. **Context for a diary of 10,000 turns and 50,000 meals**: it stays
   within its bounds and is built with bounded queries, not a full
   snapshot. (Task 2)

---

### Task 1: Coach turn storage and capture fixes

**Files:**
- Modify: `android/app/src/main/java/com/yakov103/mivu/diary/DiaryCapture.kt`, `DiaryDatabase.kt` (a `coach_undo` table and Coach turn reads)
- Test: `DiaryCaptureTest.kt` (instrumented)

**Interfaces:**
- Produces:
  - `.stored` normalization of manifest instants, plus the test
    `subSecondRetryReturnsSameTurn`;
  - `Tx.updateCoachTurn(turnID, state, assistantText, incomplete)`, ported
    from iOS `updateCoachTurn`;
  - `Tx.failCoachTurn(turnID, state)` and `Tx.finishCoachTurn(...)`;
  - `coachTurn(id)` reads;
  - the `coach_undo` table (`operationKey` primary key, payload) with
    `saveUndo` and `undoSnapshot` access.

- [ ] **Step 1: Failing tests:**
  - `subSecondRetryReturnsSameTurn`;
  - `updateCoachTurnSetsStateAndText`;
  - `finishIncompleteKeepsReceipts`;
  - `undoRowIsNotArchived`, which checks that the archive excludes
    `coach_undo` as iOS does.
- [ ] **Steps 2–4:** run (expected FAIL), implement, then run (expected
  PASS).
- [ ] **Step 5: Commit** `feat(android): store Coach turn progress and undo data`.

### Task 2: Bounded Coach context

**Files:**
- Create: `android/app/src/main/java/com/yakov103/mivu/coach/CoachContext.kt`
- Test: `CoachContextTest.kt` (instrumented)

**Interfaces:**
- Produces:
  - `@Serializable CoachContext`, ported from iOS `CoachModels.swift:189`.
    It has the same fields and JSON keys, encoded like iOS `coachJSON`
    (sorted keys).
  - `fun DiaryDatabase.coachInferenceContext(turnID): CoachContext` and
    `fun DiaryDatabase.coachHistoryMessages(turnID): List<CoachInferenceInput>`,
    ported from iOS `DiaryDatabaseCoachContext.swift`. They have all its
    bounds, `focus.lastChanged`, `focus.pendingQuestion`, `replyTo`
    resolution (including `unavailable`), and the
    `[saved key=… meal=… item=…]` assistant suffix.
  - Every query is bounded with LIMIT clauses. Nothing calls `snapshot()`.

- [ ] **Step 1: Failing tests:**
  - `contextStaysWithin60000Bytes`, on a seeded large diary (generate it in
    the test; mirror iOS `ChatHistoryFixture`);
  - `fourteenDayWindow`;
  - `fortyMealCap`;
  - `recentTurnsCapped`;
  - `replyToMealResolves`;
  - `replyToDeletedIsUnavailable`;
  - `assistantSuffixListsSavedKeys`;
  - `buildsWithoutFullSnapshot`, which asserts no `snapshot()` call through
    a test hook or by timing a 10k-turn fixture against a bound.
- [ ] **Steps 2–4:** run (expected FAIL), implement, then run (expected
  PASS).
- [ ] **Step 5: Commit** `feat(android): build bounded Coach context`.

### Task 3: Coach tools: declarations and parsing

**Files:**
- Create: `android/app/src/main/java/com/yakov103/mivu/coach/CoachTools.kt`, `CoachManualEdits.kt`, `CoachWriteFingerprint.kt`
- Test: `CoachToolsTest.kt` (JVM)

**Interfaces:**
- Produces:
  - `object CoachTools`:
    - `fun declarations(): JsonObject` returns the `mivu` namespace with all
      32 tools. The schemas are byte-for-byte equal to iOS when both are
      canonicalized. The test compares against a golden JSON that a small
      iOS test-only helper exports to `fixtures/coach/tools.json`, using the
      same pattern as the archive fixtures. Include that iOS test in this
      task.
    - `fun parse(call: CoachToolCall, seenMeals): CoachCommand` with every
      iOS validation rule.
  - `sealed CoachCommand` and `sealed CoachWrite`, with the iOS cases and
    targets.
  - `fun CoachWrite.commandFingerprint(): String`, which must equal iOS for
    the same write. A golden test uses a few fingerprints exported by the
    same iOS helper.

- [ ] **Step 1: Failing tests:**
  - `declarationsMatchIosGolden`;
  - `unknownKeyRejected`;
  - `oversizedStringRejected`;
  - `progressDaysMustBe1_7_30`;
  - `clarificationAtMost4Candidates`;
  - `candidateMustBeSeenThisTurn`;
  - `fingerprintsMatchIosGolden`;
  - one parse test per tool family.
- [ ] **Steps 2–4:** run (expected FAIL), implement, then run (expected
  PASS). Also run the iOS helper test with `xcodebuild` on your own
  simulator.
- [ ] **Step 5: Commit** `feat(android): declare and parse Coach tools`.

### Task 4: Applying Coach writes, receipts and undo

**Files:**
- Create: `android/app/src/main/java/com/yakov103/mivu/diary/CoachWrites.kt`
- Test: `CoachWritesTest.kt` (instrumented)

**Interfaces:**
- Produces:
  - `fun DiaryDatabase.validateCoachWrites(turnID, writes)`;
  - `fun DiaryDatabase.applyCoachWrites(turnID, writes): List<CoachReceipt>`;
  - `fun DiaryDatabase.undoCoachChange(operationKey)`;
  - `fun DiaryDatabase.executeCoachRead(command): JsonElement`.

  All of these are ported from iOS `DiaryDatabaseCoachMutations.swift` and
  the read handlers. They reuse the milestone 2 and 3 store operations
  (food capture, editItem, deleteItem, scaleMeal, moveMeal, deleteMeal,
  deletePhoto, setCompleteness, weight and workout writes). Add the
  weight, workout, goal and preference writes iOS uses.
- Rules:
  - all-or-nothing batch;
  - the 16-receipt cap;
  - a prior receipt with the same key is returned unchanged;
  - `resultJSON` is shaped like iOS;
  - `coach_undo` saving and undo gating.

- [ ] **Step 1: Failing tests:**
  - `logFoodCreatesMealAndReceipt`;
  - `replaySameKeyReturnsPriorReceipt`;
  - `batchFailsAtomically`;
  - `correctItemQuantity`;
  - `weightLogAndCorrect`;
  - `workoutLogEditDelete`;
  - `undoRestoresPriorState`;
  - `undoRefusedAfterLaterEdit`;
  - `receiptResultJsonValidatesInArchive`.
- [ ] **Steps 2–4:** run (expected FAIL), implement, then run (expected
  PASS).
- [ ] **Step 5: Commit** `feat(android): apply Coach writes with receipts and undo`.

### Task 5: Coach engine

**Files:**
- Create: `android/app/src/main/java/com/yakov103/mivu/coach/CoachEngine.kt`, `CoachReplyCheck.kt`, `CoachReplyLines.kt`, `CoachInference.kt`
- Modify: `analysis/ResponsesClient.kt` (`respond(model, input, tools)` with tool calls, output items and the iOS limits)
- Test: `CoachEngineTest.kt` (instrumented, with fake inference), `CoachReplyCheckTest.kt` (JVM), `ResponsesClientTest.kt` (tool-call streams)

**Interfaces:**
- Produces:
  - `class CoachEngine(db, infer: suspend (List<CoachInferenceInput>, JsonObject) -> CoachInferenceResult, models)`
    with `suspend fun run(turnID)`, ported from iOS `CoachEngine.run`. It
    has the same modes, limits, `stableRules` text (copied verbatim), input
    assembly, round loop, finalize rules and failure mapping.
  - `CoachInferenceInput` and `CoachInferenceResult`, as on iOS.
  - `ResponsesClient.respond`, which parses `function_call` and reasoning
    items and keeps the raw output items for replay.

- [ ] **Step 1: Failing tests:**
  - `textOnlyMealLogsAndCompletes`;
  - `replayModeSendsNoPhotosAndNoDuplicateWrites`;
  - `ungroundedSaveClaimRejected`;
  - `clarificationMustBeOnlyCall`;
  - `partialSuccessMarksIncomplete`;
  - `unauthorizedWaitsForConnection`;
  - `usageUnavailableNeedsRetry`;
  - `transientWaitsForNetwork`;
  - `roundLimitStops`;
  - `replyCheckRejectsUngroundedNumbers`;
  - streams with tool calls parse;
  - reasoning items are kept.
- [ ] **Steps 2–4:** run (expected FAIL), implement, then run (expected
  PASS).
- [ ] **Step 5: Commit** `feat(android): run Coach turns with Mivu's tools`.

### Task 6: Coach worker and live debug hook

**Files:**
- Create: `android/app/src/main/java/com/yakov103/mivu/coach/CoachWorker.kt`
- Modify: the debug proof screen (adds "Run Coach turn" with a synthetic text)
- Test: `CoachWorkerTest.kt` (instrumented)

**Interfaces:**
- Produces `CoachWorker`, single-flight, which follows the carried
  milestone 5 item. It resumes pending turns in order with the iOS backoff
  of 1, 2 and 4 seconds on transient errors. A network callback
  (`ConnectivityManager`) resumes it when the network returns. It does not
  hold a lock across network calls; a drain-requested flag removes
  duplicate requests instead.
- The debug proof screen can capture and run one synthetic Coach turn live
  after sign-in. That is Phase 0 evidence for real inference with tools.

- [ ] **Step 1: Failing tests:**
  - `resumesPendingAfterRestart`;
  - `transientBacksOff`;
  - `duplicateDrainRequestsCoalesce`.
- [ ] **Steps 2–4:** run (expected FAIL), implement, then run (expected
  PASS).
- [ ] **Step 5: Commit** `feat(android): resume Coach turns in the background`.

### Task 7: Evidence and parity

- [ ] Run the full suite. Record `docs/verification/2026-10-24-android-coach-engine.md`.
  Mark `coach-context` and `coach-edit-parity` Android `partial` (engine
  done, UI pending, milestone 4b). Remove the delivered items from
  `android-carried-items.md`. Commit `docs(verification): record the Android Coach engine`.
