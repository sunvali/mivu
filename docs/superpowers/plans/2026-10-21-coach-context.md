# Coach Context Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Coach knows what "it" means. It acts on the clear referent with an Undo, asks once with tappable choices when it genuinely must, and never shows a failure after something saved.

**Architecture:**
- History moves out of the context JSON and into real `user` and `assistant` messages, each carrying a line of receipt IDs.
- A per-turn `focus` object goes in a trailing developer message after the stable rules. It holds `replyTo` (from #39), `lastChanged` (stamped on meals by diary revision) and `pendingQuestion` (persisted on the asking turn).
- New tools reuse the existing parse, validate and apply pipeline:
  - `scale_meal`, `find_meals` and `undo_change`
  - clarification `candidates` and the `confirm` kind
- Undo snapshots live in a new `coach_undo` table, so receipts stay immutable.

**Tech Stack:** Swift 6, SwiftUI, SQLite via `DiaryDatabase`, Responses API (`store: false`), XCTest/XCUITest.

**Spec:** `docs/superpowers/specs/2026-10-21-coach-context-design.md`

## Global Constraints

- The base is `feat/coach-reply` (#39). Rebase onto `main` once #39 merges. `CoachReply`, `CoachContext.replyTo` and `CoachExchangeSummary.reply` come from it.
- Keep `store: false`. Do not add `previous_response_id` or Conversations.
- Each history exchange is capped at 1 KB of text, and all history at 8 KB. The context JSON cap stays at 60 KB, and history must not be added on top of it.
- `lastChanged` counts food changes only, and only within the active waking day (`context.activeDayID`).
- Undo covers food only: log, append, edit, correct, scale and delete item. A whole-meal delete gets no Undo, because AGENTS.md says never to restore over deletions.
- Text for receipts and clarifications stays app-generated. Keep the `ungroundedConfirmation` guard.
- Clarification copy:
  - `confirm`: "Remove the whole <meal name> meal?" with buttons "Remove" and "Keep".
  - Choice kinds: "Which one did you mean?"
- Partial-failure line: "Couldn't finish the rest" plus a "Retry" button.
- `scale_meal` refuses when known kcal is 0, the meal has an unaccepted review, or the ratio falls outside 0.1–3. Quantities round to 2 decimals.
- `find_meals` returns at most 10 meals, newest first.
- Every new write needs a manual equivalent (coach-edit parity).
- Dynamic Type, VoiceOver, 44-pt targets and Precision Glass tokens apply. Use synthetic data only. Do not mention AI in commits.

## Review Focus

1. **A meal changed by hand after Coach changed it.** Undo must hide (revision mismatch) and never overwrite the manual edit. Test: `CoachUndoTests.undoHiddenAfterManualEdit` (Task 8).
2. **Day rollover.** `lastChanged` from yesterday must be absent today. Test: `CoachFocusTests.lastChangedAbsentAfterRollover` (Task 2).
3. **A chip tapped after the candidate meal was deleted.** The reply resolves as `unavailable` (#39 behavior), and Coach asks rather than editing another meal. Test: `CoachClarificationTests.deletedCandidateReplyIsUnavailable` (Task 3).
4. **Retry after a partial save.** Already-saved foods must not be logged twice. Test: `CoachPartialSuccessTests.retryDoesNotReapplyReceipts` (Task 4).
5. **Scaling a meal with an item of unknown kcal.** It scales by the known kcal and says so, never claiming an exact total. Test: `CoachScaleMealTests.unknownKcalItemScalesQuantityOnly` (Task 6).

## Test command

Run on a dedicated simulator, never a shared one: create it with `xcrun simctl create`, then delete it at the end.

`xcodebuild test -project ios/Mivu.xcodeproj -scheme Mivu -testPlan Mivu -destination "id=$SIM" -only-testing:<Target>/<Class>[/<test>] -resultBundlePath <workspace>/<name>.xcresult`

Below, `RUN <Target>/<Class>` means this command.

---

### Task 1: History as messages, stable prefix

**Files:**
- Modify:
  - `ios/Mivu/Coach/CoachModels.swift` (`CoachContext.Turn`)
  - `ios/Mivu/Diary/DiaryDatabaseCoachContext.swift` (recent-turn loop, ~line 131)
  - `ios/Mivu/Coach/CoachEngine.swift` (input assembly, lines 26-29)
- Test: `ios/MivuTests/CoachContextMessagesTests.swift` (new)

**Interfaces:**
- Produces:
  - `CoachContext.Turn.receipts: String?`: one line, `[saved key=<operationKey> meal=<uuid> item=<uuid?>; …]`, nil when the turn has no receipts.
  - `CoachEngine.historyMessages(_ turns: [CoachContext.Turn]) -> [CoachInferenceInput]`: for each turn, a `.user` message (text, or "[photo]" when the text is empty), then a `.assistant` message (`assistantText` plus a newline plus `receipts`) when either is present.
  - `CoachEngine.stableRules: String`: a static string with no per-turn values.

- [ ] **Step 1: Write the failing tests.**
  - `historyBecomesMessagesBeforeContext`: a turn whose context has 2 recent turns, one with a receipt. Assert:
    - `input[0]` is `.message(.developer, stableRules)`.
    - `input[1...4]` alternate user and assistant.
    - The assistant message contains `meal=<id>`.
    - The next element is a developer message starting with `"Context: "` whose JSON has `"recentTurns":[]`.
    - The last element is the current user text.
  - `stablePrefixIsIdenticalAcrossTurns`: two runs with different `capturedAt` produce byte-identical `input[0]` text.
  - `historyRespects8KBCap`: 12 turns of 1 KB keep total history text at or under 8192 bytes, with the oldest dropped first.
  - Capture the inputs with the existing fake `infer` closure pattern from `CoachEngineTests`.
- [ ] **Step 2:** Run `RUN MivuTests/CoachContextMessagesTests`. Expected: FAIL (compile error, missing `receipts`/`stableRules`).
- [ ] **Step 3: Implement.**
  - Fill `receipts` in the recent-turn loop from `turn.receipts`. Count the receipt line inside the existing 8192-byte trim.
  - In `CoachEngine.run`:
    - Split the current developer text into `stableRules`.
    - Move `WakingDayInstruction.text(...)` and the conditional `replyTo` sentence into the tail developer message, before `"Context: "`.
    - Encode a copy of `context` with `recentTurns = []`.
- [ ] **Step 4:** Run `RUN MivuTests/CoachContextMessagesTests` and `RUN MivuTests/CoachEngineTests`. Expected: PASS. If existing tests assert prompt substrings, update their expected positions only.
- [ ] **Step 5:** Commit `feat(coach): send recent exchanges as chat messages with receipt ids`.

### Task 2: Focus — lastChanged and the resolution policy

**Files:**
- Modify:
  - `ios/Mivu/Diary/DiaryModels.swift` (`DiaryMeal`)
  - `ios/Mivu/Diary/DiaryDatabaseMealMutations.swift` (`saveMeal` and the meal insert at ~line 338)
  - `ios/Mivu/Coach/CoachModels.swift` (`CoachContext`)
  - `ios/Mivu/Diary/DiaryDatabaseCoachContext.swift`
  - `CoachEngine.stableRules`
- Test: `ios/MivuTests/CoachFocusTests.swift` (new)

**Interfaces:**
- Produces:
  - `DiaryMeal.changedRevision: Int?`: set to the committing head revision (`head.revision + 1`) on every meal insert or save. Optional, so old payloads decode.
  - `CoachContext.Focus { lastChanged: LastChanged?; pendingQuestion: CoachQuestion? }`, with `LastChanged { mealID: UUID; itemNames: [String]; localDate: String; revision: Int }`.
  - `CoachContext.focus: Focus?`, nil when both fields are nil.
  - `struct CoachQuestion: Codable, Equatable, Sendable { var kind: CoachClarification; var candidates: [CoachReply.Target]; var originalText: String }`, with `CoachClarification` made Codable. Task 2 defines it, and `pendingQuestion` stays nil until Task 3 fills it.

- [ ] **Step 1: Write the failing tests.**
  - `lastChangedIsMostRecentMealToday`: two meals in the active day; edit the older one by hand. Assert `focus.lastChanged.mealID` is the edited meal.
  - `lastChangedAbsentAfterRollover`: change a meal, then roll the active day (existing rollover helper). Assert `focus == nil`.
  - `stableRulesStateResolutionOrder`: `stableRules` contains "explicit mention, then replyTo, then pendingQuestion, then focus.lastChanged, then the newest matching meal". It no longer contains "Omitted or paginated evidence cannot establish uniqueness" or "Ask when the matching food or serving is ambiguous."
- [ ] **Step 2:** Run `RUN MivuTests/CoachFocusTests`. Expected: FAIL.
- [ ] **Step 3: Implement.**
  - Stamp `changedRevision`.
  - In `coachInferenceContext`, choose the meal in the active day with the highest `changedRevision` and state `saved`. This is one bounded query over that day's meals.
  - Rewrite the two removed sentences as this rule:

    "Resolve which record the user means in this order: explicit mention, then replyTo, then pendingQuestion, then focus.lastChanged, then the newest matching meal. When one record clearly wins, act on it. Ask only when two candidates genuinely tie or before deleting a whole meal. Truncated context is not ambiguity: use get_meals_for_date or find_meals."
- [ ] **Step 4:** Run `RUN MivuTests/CoachFocusTests`, `RUN MivuTests/CoachEngineTests` and `RUN MivuTests/CoachIndexedContextTests`. Expected: PASS.
- [ ] **Step 5:** Commit `feat(coach): track the last changed meal as conversation focus`.

### Task 3: Clarification candidates, confirm, and pendingQuestion

**Files:**
- Modify:
  - `ios/Mivu/Coach/CoachTools.swift` (`CoachClarification`, `ask_clarification` schema and parse)
  - `ios/Mivu/Coach/CoachModels.swift` (`CoachTurn`, `CoachExchangeSummary` via `CoachTimelineModels.swift`)
  - `ios/Mivu/Coach/CoachEngine.swift` (clarification branch, ~line 85)
  - `ios/Mivu/Diary/DiaryStore.swift` (`finishCoachTurn`)
  - the context builder
- Test: `ios/MivuTests/CoachClarificationTests.swift` (new)

**Interfaces:**
- Produces:
  - `CoachClarification` gains `case confirm`.
  - Uses `CoachQuestion` from Task 2.
  - `CoachTurn.question: CoachQuestion?` and `CoachExchangeSummary.question: CoachQuestion?`.
  - `ask_clarification` args: `kind` (required) and `candidates` (optional, ≤4 objects `{meal_id, item_id?}`). Every ID must be in `knownMeals`. `confirm` requires exactly one meal candidate.
  - `CoachCommand.clarification(CoachClarification, candidates: [CoachReply.Target])`.
  - `DiaryStore.finishCoachTurn(turnID:assistantText:question:epoch:expectedProfileID:)`, where `question` defaults to nil.
  - Question text:
    - `confirm`: "Remove the whole \(itemNames joined by ", ") meal?"
    - Any kind with candidates: "Which one did you mean?"
    - Otherwise: the existing `kind.question`.
  - The context builder sets `focus.pendingQuestion` from the immediately previous turn when it is completed and has a `question`.
  - **A clarification after a write no longer throws.** The turn finishes with the committed summary plus a newline plus the question, state `completed`.

- [ ] **Step 1: Write the failing tests.**
  - `candidatesPersistAndFeedNextTurn`: a fake model asks `meal` with 2 candidates. Assert the stored turn's `question.candidates.count == 2` and `assistantText == "Which one did you mean?"`. The next turn's context has `focus.pendingQuestion.originalText ==` the first turn's text.
  - `confirmUsesMealName`: a meal with item "Snickers Minis" gives "Remove the whole Snickers Minis meal?".
  - `unknownCandidateRejected`: a random UUID produces `CoachError.invalidArguments`.
  - `clarificationAfterWriteCompletes`: round 1 calls `log_food`, round 2 calls `ask_clarification(portion)`. Assert the state is `.completed`, the text contains the receipt summary and the portion question, and no throw.
  - `deletedCandidateReplyIsUnavailable`: delete the candidate meal, then send a reply turn targeting it. Assert `context.replyTo.unavailable == true`.
- [ ] **Step 2:** Run `RUN MivuTests/CoachClarificationTests`. Expected: FAIL.
- [ ] **Step 3: Implement.**
  - Update the `delete_item` tool description in `CoachManualEdits.swift`: "…for the only food use ask_clarification kind confirm with that meal".
- [ ] **Step 4:** Run `RUN MivuTests/CoachClarificationTests`, `RUN MivuTests/CoachEngineTests` and `RUN MivuTests/CoachManualEngineTests`. Expected: PASS.
- [ ] **Step 5:** Commit `feat(coach): clarifications carry candidates and resume the original request`.

### Task 4: Show what saved

**Files:**
- Modify:
  - `ios/Mivu/Coach/CoachEngine.swift` (`catch`)
  - `CoachTurn` / `CoachExchangeSummary` (`incomplete: Bool?`)
  - `ios/Mivu/Coach/CoachViewModel.swift`
  - `ios/Mivu/Coach/CoachTimelineView.swift`
- Test: `ios/MivuTests/CoachPartialSuccessTests.swift` (new), plus `ios/MivuUITests/CoachUITests.swift`

**Interfaces:**
- Produces:
  - `CoachTurn.incomplete: Bool?` and `CoachExchangeSummary.incomplete: Bool?`.
  - **Engine.** When the turn has receipts and the error is not cancellation or a profile change, finish the turn with `coachCommittedSummary`, `incomplete = true` and state `.completed`, instead of `failCoachTurn`.
  - **Timeline.** Under an incomplete exchange, show the secondary line "Couldn't finish the rest" and a "Retry" button (id `coachFinishRest`, at least 44 pt).
  - **Retry.** Compose a new turn with the original turn's text and reply target `.message(turnID:, fromPip: true)`.
  - **Rule added to `stableRules`:** "When replyTo is a turn that already saved items, do only what is still missing."

- [ ] **Step 1: Write the failing tests.**
  - `writeThenFailureCompletesIncomplete`: round 1 `log_food`, round 2 an invalid tool. Assert state `.completed`, `incomplete == true` and the receipt kept.
  - `retryDoesNotReapplyReceipts`: retry through the view model. The fake model sees `replyTo.turn.receipts` and the meal count stays 1.
  - UI test `testPartialSuccessShowsSavedCardAndRetry` (`CoachUITestInference` scenario `partial`): the receipt card exists, "Analysis could not finish" does not, and `coachFinishRest` is hittable.
- [ ] **Step 2:** Run `RUN MivuTests/CoachPartialSuccessTests`. Expected: FAIL.
- [ ] **Step 3: Implement.** Add scenario `partial` to `CoachUITestInference`, following its existing scenarios.
- [ ] **Step 4:** Run `RUN MivuTests/CoachPartialSuccessTests` and `RUN MivuUITests/CoachUITests/testPartialSuccessShowsSavedCardAndRetry`. Expected: PASS.
- [ ] **Step 5:** Commit `fix(coach): a turn that saved food never reports failure`.

### Task 5: Tappable clarification chips

**Files:**
- Create: `ios/Mivu/Coach/CoachQuestionChips.swift`
- Modify: `ios/Mivu/Coach/CoachTimelineView.swift`, `ios/Mivu/Coach/CoachViewModel.swift`
- Test: `ios/MivuUITests/CoachClarificationUITests.swift` (new)

**Interfaces:**
- Consumes: `CoachExchangeSummary.question` (Task 3) and the #39 composer reply send path.
- Produces:
  - `struct CoachQuestionChips: View` with `(question: CoachQuestion, meals: [MealReadModel], onPick: (CoachReply.Target, String) -> Void)`.
  - Each chip shows the thumbnail (the existing meal-photo helper used by `MealRow`), the name and the time. The id is `coachQuestionChip`.
  - `confirm` renders the buttons "Remove" (`coachConfirmRemove`, destructive tint) and "Keep" (`coachConfirmKeep`).
  - `CoachViewModel.answer(_ target: CoachReply.Target, label: String)` sends a turn with text `label` and reply `target`.
  - "Keep" sends the text "Keep it" with the reply target set to the meal.
  - Chips show only on the latest exchange, when its `question` has candidates.

- [ ] **Step 1: Write the failing UI test.** `testChipTapResumesOriginalRequest`, using scenario `clarify-candidates`. The fake asks with 2 candidates, then on the next turn asserts `pendingQuestion` and calls `correct_item`. Tap the first `coachQuestionChip`, then assert a receipt card appears. Also `testConfirmRemoveDeletesMeal` with scenario `clarify-confirm`.
- [ ] **Step 2:** Run `RUN MivuUITests/CoachClarificationUITests`. Expected: FAIL.
- [ ] **Step 3: Implement.** Add the view and the two `CoachUITestInference` scenarios.
- [ ] **Step 4:** Run `RUN MivuUITests/CoachClarificationUITests`. Expected: PASS. Check the largest Dynamic Type in one run.
- [ ] **Step 5:** Commit `feat(coach): tappable choices for clarifying questions`.

### Task 6: scale_meal, the tool and the manual action

**Files:**
- Modify:
  - `ios/Mivu/Coach/CoachManualEdits.swift` (new case, schema, parse)
  - `ios/Mivu/Diary/DiaryDatabaseMealMutations.swift`
  - `ios/Mivu/Diary/DiaryStore.swift`
  - `ios/Mivu/Diary/DiaryDatabaseCoachMutations.swift` (preflight, apply, replay)
  - `CoachWriteFingerprint.swift`
  - `ios/Mivu/Diary/MealDetailView.swift`
- Test: `ios/MivuTests/CoachScaleMealTests.swift` (new), `ios/MivuTests/CoachEditParityTests.swift`, `ios/MivuUITests/DiaryAmountEditorUITests.swift`

**Interfaces:**
- Produces:
  - `DiaryTransaction.scaleMeal(mealID: UUID, targetKcal: Double, expectedRevision: Int) throws -> DiaryMeal`:
    - ratio = `targetKcal / knownKcal`
    - each item gets `diaryCorrectedItem(item with quantity = (q*ratio) rounded to 2dp, previous: item, explicitNutrients: [])`
    - commits through `commitSavedItems`
    - throws `DiaryError.invalidData` when known kcal is 0, the meal is not `.saved`, or the ratio is not in 0.1...3
  - `DiaryStore.scaleMeal(mealID:targetKcal:expectedRevision:expectedProfileID:)`.
  - `CoachManualEdit.scaleMeal(mealID:targetKcal:revision:)`, with target `"scale_meal/\(id)"` and tool `scale_meal` taking `meal_id`, `target_kcal`, `expected_revision`.
  - The tool description says it changes the whole meal's portions proportionally.
  - **Meal detail.** Add an "Adjust total" button (id `adjustMealTotal`) in the summary card. It opens a sheet with a kcal field (`mealTargetKcal`), a live preview of the new total, and "Save" (`saveMealTotal`).

- [ ] **Step 1: Write the failing tests.**
  - `scalesTwoItemsTo650`: 600 + 245 kcal becomes a total between 640 and 660, and the quantity ratio is about 0.769 for both items.
  - `refusesPendingReview`, `refusesZeroKcal` and `refusesRatioAbove3`.
  - `unknownKcalItemScalesQuantityOnly`: an item with nil kcal also gets the quantity ratio, and the ratio is computed from the known items.
  - Parity: `scale_meal` via Coach equals the manual result.
  - UI: `testAdjustMealTotal` saves 650 and the summary shows "650 kcal" (±10).
- [ ] **Step 2:** Run `RUN MivuTests/CoachScaleMealTests`. Expected: FAIL.
- [ ] **Step 3: Implement.** Follow the `delete_item` pattern from the diary redesign: case, fingerprint, preflight, apply, replay suffix check.
- [ ] **Step 4:** Run `RUN MivuTests/CoachScaleMealTests`, `RUN MivuTests/CoachEditParityTests`, `RUN MivuTests/CoachManualEngineTests` and `RUN MivuUITests/DiaryAmountEditorUITests/testAdjustMealTotal`. Expected: PASS.
- [ ] **Step 5:** Commit `feat(diary): scale a whole meal to a target total, by hand or via Coach`.

### Task 7: find_meals

**Files:**
- Modify:
  - `ios/Mivu/Coach/CoachTools.swift` (declaration, `CoachCommand.findMeals`, parse)
  - `ios/Mivu/Coach/CoachEngine.swift` (dispatch)
  - `ios/Mivu/Diary/DiaryDatabaseCoachContext.swift`
  - `ios/Mivu/Diary/DiaryStore.swift`
- Test: `ios/MivuTests/CoachFindMealsTests.swift` (new)

**Interfaces:**
- Produces:
  - `DiaryStore.coachFindMeals(query: String, from: String?, to: String?, expectedProfileID: UUID) throws -> [CoachMealCandidate]`:
    - case-insensitive match on item name
    - newest first
    - at most 10 results
    - `from`/`to` are inclusive local dates
  - Tool `find_meals` takes `query` (≤100 chars), `from_date` and `to_date`.

- [ ] **Step 1: Write the failing tests.**
  - `findsByNameNewestFirst`: with 12 "pizza" meals, return 10, newest first.
  - `respectsDateRange`.
  - `rejectsLongQuery`: 101 characters gives `invalidArguments`.
- [ ] **Step 2:** Run `RUN MivuTests/CoachFindMealsTests`. Expected: FAIL.
- [ ] **Step 3: Implement.** Build on the SQL pattern in `coachMeals(on:)`. Add the found meals to `knownMeals` the same way `.meal` does.
- [ ] **Step 4:** Run `RUN MivuTests/CoachFindMealsTests` and `RUN MivuTests/CoachEngineTests`. Expected: PASS.
- [ ] **Step 5:** Commit `feat(coach): find meals by name for older references`.

### Task 8: Undo for Coach food changes

**Files:**
- Modify:
  - `ios/Mivu/Diary/DiaryDatabase.swift` (`CREATE TABLE IF NOT EXISTS coach_undo`, next to the `coach_turn` creation)
  - `ios/Mivu/Diary/DiaryDatabaseCoachMutations.swift` (snapshot on apply)
  - `ios/Mivu/Diary/DiaryStore.swift`
  - `ios/Mivu/Coach/CoachManualEdits.swift` (`undo_change`)
  - `ios/Mivu/Coach/CoachReceiptView.swift`
  - `ios/Mivu/Coach/CoachViewModel.swift`
- Test: `ios/MivuTests/CoachUndoTests.swift` (new), `ios/MivuUITests/CoachUITests.swift`

**Interfaces:**
- Produces:
  - Table `coach_undo(operationKey TEXT PRIMARY KEY, turnID TEXT NOT NULL REFERENCES coach_turn(id) ON DELETE CASCADE, mealID TEXT NOT NULL, afterRevision INTEGER NOT NULL, beforePayload BLOB, undone INTEGER NOT NULL DEFAULT 0)`.
    - `beforePayload` is the JSON `[FoodItem]` before the change.
    - It is NULL for `log_food`, where Undo deletes the meal.
  - Snapshots are written in the same transaction as each food receipt: log, append, edit item, correct, scale, delete item.
  - `DiaryStore.coachUndoAvailable(operationKey: String, expectedProfileID: UUID) throws -> Bool` is true when the row exists, it is not undone, and the meal's current revision equals `afterRevision`.
  - `DiaryStore.undoCoachChange(operationKey: String, expectedProfileID: UUID) throws`:
    - restores with `commitSavedItems(before, expectedRevision: afterRevision)`, or deletes the meal for a log
    - sets `undone = 1`
    - throws `DiaryError.staleRevision` when the revision differs
  - The Coach tool `undo_change(operation_key)` is accepted only for food keys. It is a write with target `"undo/\(operationKey)"`.
  - **Receipt card.** An "Undo" button (id `coachUndo`) shows when available. After an undo, the status reads "Undone".

- [ ] **Step 1: Write the failing tests.**
  - `undoCorrectionRestoresItems`.
  - `undoLogDeletesMeal`.
  - `undoHiddenAfterManualEdit`: a manual edit bumps the revision, so available is false and undo throws `staleRevision`.
  - `undoChangeToolUndoesLastReceipt`.
  - `weightReceiptHasNoUndo`.
  - UI `testReceiptUndo`: tap `coachUndo` and assert "Undone".
- [ ] **Step 2:** Run `RUN MivuTests/CoachUndoTests`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4:** Run `RUN MivuTests/CoachUndoTests`, `RUN MivuTests/CoachBatchTransactionTests`, `RUN MivuTests/CoachRecoveryReviewTests` and `RUN MivuUITests/CoachUITests/testReceiptUndo`. Expected: PASS.
- [ ] **Step 5:** Commit `feat(coach): undo food changes from the receipt card or by asking`.

### Task 9: Docs and verification

**Files:**
- Modify: `docs/development/coach-chat-behavior.md` (history, focus, resolution order, clarification, partial success, undo).
- Create: `docs/verification/2026-10-21-coach-context.md`.

- [ ] **Step 1:** Update the behavior doc to match Tasks 1–8.
- [ ] **Step 2:** Run the full suite once with the test plan `Mivu` on a dedicated simulator. Record the SHA, the counts, and each failure classified against `main`.
- [ ] **Step 3: Manual on-device replay** of the spec's three transcripts on the owner's iPhone build, using the owner's own ChatGPT connection. Record the outcome of each. The owner runs it. If it is not run, record it as blocked.
- [ ] **Step 4:** Commit `docs(coach): context behavior and verification`.
