# Coach Delete Undo and Visible Food Delete Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every destructive Coach write gets a short-lived Undo that fully restores the deleted record, and each saved food row in meal detail gets a visible delete button.

**Architecture:**
- Before each destructive Coach write, a snapshot is stored in a new derived table, `coach_undo_deleted`, in the same transaction. Like `coach_undo`, this table is never archived.
- Undo recreates the record under new IDs, using the existing creators. Tombstones never shrink.
- Availability is derived from the turn order and a 10-minute wall clock. Purge runs on capture and on open.
- The food-row button only sets the existing `deletion` state in `MealDetailView`.

**Tech Stack:** Swift 6, SwiftUI, SQLite3 (`DiaryDatabase`), Swift Testing (`ios/MivuTests`), XCUITest (`ios/MivuUITests`). Tests run through XcodeBuildMCP.

**Spec:** `docs/superpowers/specs/2026-10-29-coach-delete-undo-design.md`

## Global Constraints

- Undo window: the button shows only while no newer turn exists in the profile. The snapshot survives exactly one more turn, for voice undo. Anything older than **600 seconds** (wall clock, from `DiaryStore.currentTime`) is unavailable and purged.
- Restored records get **new IDs**. Never delete a row from `tombstone`, `weight_tombstone` or `workout_tombstone`.
- `coach_undo_deleted` is created with `CREATE TABLE IF NOT EXISTS`, beside `coach_undo` (`DiaryDatabase.swift:57`), outside the version gate. Add `turnID … REFERENCES coach_turn(id) ON DELETE CASCADE`. Never read it from the archive, backup or report code.
- Restore conflict rules:
  - meal: always recreated;
  - photo: re-attach to the original meal if it exists, else `DiaryError.notFound`;
  - weight: `DiaryError.staleRevision` if that day already has a weight;
  - workout: always recreated.
- If the snapshot would exceed `maximumBytes`, the delete still commits without a snapshot.
- Delete tool results include `"undo_key": <operationKey>` and `"undo_until": "next message"`.
- The food-row button is manual only, with no Undo. It uses `.food(item, revision:)` when the meal has more than one item, otherwise `.meal`. It is shown only when `meal.state == .saved`. It is at least 44 pt, labeled "Delete <name>", with accessibility identifier `deleteFood`.
- Use only synthetic test data. Never use the words "codex" or "ai" in commits. Commit titles follow Conventional Commits.

## Review Focus

1. Undo tapped twice quickly, or button and voice racing. Expect exactly one restore; the second attempt fails with `staleRevision`. (Test in Task 3.)
2. App relaunched more than 10 minutes after a delete. Expect no Undo and no held bytes. (Task 2 tests purge on open.)
3. Meal deleted with photos, then the same photo bytes appear in a backup or export while held. Expect them absent. (Task 1 asserts `snapshotForExport()` has no held data.)
4. Voice "undo that" in the very next message. Expect it to work; one message later it fails. (Task 3.)
5. Undoing the undo of a logged meal. Expect the meal to come back under a new ID. (Task 3.)

---

### Task 1: Snapshot table and capture at delete time

**Files:**
- Modify: `ios/Mivu/Diary/DiaryDatabase.swift:57` (add the table)
- Modify: `ios/Mivu/Diary/DiaryDatabaseCoachMutations.swift:5-31` (`applyCoachWrites` loop), `:339-346` (`undoCoachChange` delete branch)
- Create: `ios/Mivu/Diary/DiaryCoachDeletedUndo.swift` (snapshot type and transaction helpers)
- Test: `ios/MivuTests/CoachDeleteUndoTests.swift`

**Interfaces:**
- Produces:
  - `enum CoachDeletedSnapshot: Codable, Sendable { case meal(DiaryMeal, items: [FoodItem], photos: [MealPhoto]); case photo(mealID: UUID, MealPhoto); case weight(WeightEntry); case workout(WorkoutSession) }`
  - `extension DiaryTransaction { func deletedSnapshot(_ write: CoachWrite) throws -> CoachDeletedSnapshot? }` returns nil for non-destructive writes. For `.undo(key)` it returns a `.meal` snapshot only when that undo will delete a whole meal (`coachUndo(key)?.before == nil`).
  - `func saveDeletedUndo(key: String, turnID: UUID, snapshot: CoachDeletedSnapshot, at: Date) throws`
  - Table columns: `operationKey TEXT PRIMARY KEY, turnID TEXT NOT NULL REFERENCES coach_turn(id) ON DELETE CASCADE, payload BLOB NOT NULL, createdAt REAL NOT NULL, restoredID TEXT, undone INTEGER NOT NULL DEFAULT 0`.

Steps:

- [ ] **Step 1: Write the failing tests**
  - Model on `CoachUndoTests.fixture()`. Apply each delete through `store.applyCoachWrites` (`DiaryStore.swift:531`) on a captured turn.
  - `@Test func deleteMealHoldsSnapshotWithPhotos()`:
    - meal with 2 items and `MealPhoto(data: Data([1,2,3]))`, then Coach `.manual(.deleteMeal(id, revision))`;
    - `#expect(try await store.coachUndoAvailable(operationKey: receipt.operationKey, expectedProfileID: profile.id))`;
    - `#expect(try await store.snapshotForExport().meals.contains { $0.id == meal.id } == false)`;
    - exported JSON (`DiaryArchive.encode`) does not contain the bytes `[1,2,3]` base64 (`"AQID"`).
  - `@Test func deleteWeightAndWorkoutHoldSnapshots()`: both report `coachUndoAvailable == true`.
  - `@Test func undoOfLoggedMealHoldsSnapshot()`: use `logged(...)`, then `.undo(foodKey)` in a new turn. That undo's receipt key is available.
- [ ] **Step 2: Run and confirm failure.** Run with XcodeBuildMCP, `-only-testing:MivuTests/CoachDeleteUndoTests`. Expect FAIL: `coachUndoAvailable` returns false.
- [ ] **Step 3: Implement.**
  - Add the table.
  - In the `applyCoachWrites` loop, before `applyCoachWrite`, call `let held = try transaction.deletedSnapshot(write)`. After the receipt key is set, call `saveDeletedUndo` when `held != nil`.
  - Read photo bytes the same way `DiaryDatabaseMealMutations.swift:162` builds `MealPhoto`s from references.
  - Quota: skip `saveDeletedUndo` when the encoded payload plus current accounted bytes exceeds `maximumBytes`. Add one line: `// Coach deletes are never blocked by Undo bookkeeping.`
- [ ] **Step 4: Extend `coachUndoState(_:)`** (`DiaryDatabaseCoachMutations.swift:333`) to consult `coach_undo_deleted` first. Return `.undone` if undone, `.available` if held, nil otherwise. Expiry comes in Task 2. Run the tests: PASS.
- [ ] **Step 5: Commit** `feat(coach): hold a snapshot when the Coach deletes a record`

### Task 2: Expiry and purge

**Files:**
- Modify: `ios/Mivu/Diary/DiaryCoachDeletedUndo.swift`, `ios/Mivu/Diary/DiaryDatabaseCoachMutations.swift:333` (`coachUndoState`)
- Modify: the capture path behind `DiaryStore.captureCoachSubmission`, and the profile-open path in `DiaryStore`
- Test: `ios/MivuTests/CoachDeleteUndoTests.swift`

**Interfaces:**
- Consumes: Task 1 table and `saveDeletedUndo`.
- Produces:
  - `func purgeDeletedUndo(now: Date, keepTurnID: UUID?) throws` deletes rows with `createdAt < now - 600`, and rows whose turn is older than `keepTurnID`.
  - `func deletedUndoUsable(key: String, now: Date, forVoiceFromTurn: CoachTurn?) throws -> Bool`.
  - Button availability means "within 600 s, and no newer turn than the row's turn".
  - Voice availability means "within 600 s, and the row's turn is the immediately previous turn, or the same turn".

Steps:

- [ ] **Step 1: Write the failing tests.** Use a mutable clock box in `DiaryStore(directory:currentTime:)`.
  - `@Test func undoExpiresAfterTenMinutes()`: advance the clock 601 s. Expect `coachUndoAvailable == false`, then reopen the store and expect the row count to be 0. Add a test-only `heldDeletedUndoCount(expectedProfileID:)` behind `#if DEBUG`, or query through an existing debug read.
  - `@Test func buttonHidesAfterNextMessageButRowSurvivesOneTurn()`: capture turn B. Expect `coachUndoAvailable == false` and the held count to be 1. Capture turn C. Expect the held count to be 0.
- [ ] **Step 2: Run and confirm failure.** Expect FAIL.
- [ ] **Step 3: Implement.**
  - Call `purgeDeletedUndo(now:keepTurnID: previousTurnID)` inside the capture transaction and when a profile opens.
  - Apply the button rule in `coachUndoState`.
- [ ] **Step 4: Run and confirm pass.**
- [ ] **Step 5: Commit** `feat(coach): expire held deletes after the next message or ten minutes`

### Task 3: Restore, both as a direct undo and through the model's `undo_change`

**Files:**
- Modify: `ios/Mivu/Diary/DiaryDatabaseCoachMutations.swift`:
  - `:175-177` (`validate .undo`)
  - `:339-346` (`undoCoachChange`)
  - `:426-430` (`apply .undo` receipt)
  - `:289-293`, `:376`, `:395` (delete receipts' `resultJSON` gains `undo_key` and `undo_until`)
- Modify: `ios/Mivu/Coach/CoachManualEdits.swift:206-211` (key allowlist)
- Test: `ios/MivuTests/CoachDeleteUndoTests.swift`, `ios/MivuTests/CoachUndoTests.swift` (allowlist)

**Interfaces:**
- Consumes: the Tasks 1–2 helpers.
- Produces:
  - `undoCoachChange(_ key: String) throws -> UUID?` returns the new meal ID for meal and photo restores. For weight and workout it returns nil but sets `receipt.weightID`/`receipt.workoutID` in `apply .undo`.
  - The allowlist adds `"delete_meal/", "delete_photo/", "delete_weight/", "delete_workout/", "undo/"`.

Steps:

- [ ] **Step 1: Write the failing tests.**
  - `@Test func undoRestoresMealUnderNewIDWithPhotos()`: after undo, there is exactly one meal with the same name, items (`name`, `quantity`, `kcal`), `dayID` and photo bytes, and `id != meal.id`. The `tombstone` still contains `meal.id`. `coachUndoState` is `.undone`.
  - `@Test func undoRestoresPhotoToExistingMeal()` and `@Test func photoUndoRefusedWhenMealGone()` (expect `notFound`).
  - `@Test func weightUndoRefusedWhenDayHasWeight()` (expect `staleRevision`) and `@Test func workoutUndoAlwaysRestores()`.
  - `@Test func secondUndoIsStale()`: undo twice, and the second throws `staleRevision`.
  - `@Test func voiceUndoWorksNextMessageOnly()`:
    - `.undo(deleteKey)` applied in turn B succeeds;
    - the same in turn C (a fresh fixture) throws `staleRevision` or `invalidArguments`.
  - `@Test func undoOfUndoRecreatesLoggedMeal()`.
  - In `CoachUndoTests`: `undo_change` parsing accepts `"<uuid>/delete_meal/<uuid>"` and still rejects `"<uuid>/open_settings/x"`.
  - Delete receipt `resultJSON` contains `"undo_key"`.
- [ ] **Step 2: Run and confirm failure.**
- [ ] **Step 3: Implement.**
  - `undoCoachChange` branches on whether `coach_undo_deleted` has the key. Restore with `insertMeal` plus item save, `insertPhoto(_:owner: .meal(newID))`, `setWeight(dayID:value:unit:expectedRevision: nil, measuredAt:)`, and `createWorkout(dayID:draft:performedAt:)`.
  - Re-resolve a missing day with `coachDay`/`resolveDay`.
  - Set `undone = 1` and `restoredID`.
  - `validate .undo` uses `deletedUndoUsable(…forVoiceFromTurn: turn)` for held keys.
- [ ] **Step 4: Run** `CoachDeleteUndoTests` and `CoachUndoTests`, and expect PASS.
- [ ] **Step 5: Commit** `feat(coach): undo Coach deletes by button or by asking Pip`

### Task 4: Receipt cards show Undo for delete receipts

**Files:**
- Modify: `ios/Mivu/Coach/CoachViewModel.swift:679`. Change the key filter from `$0.mealID != nil` to `$0.mealID != nil || $0.weightID != nil || $0.workoutID != nil`.
- Modify: `ios/Mivu/Coach/CoachReceiptView.swift:219-224` only if delete receipts don't reach that branch. Verify with the UI test.
- Test: `ios/MivuUITests/CoachNavigationUITests.swift`, a new test that uses the existing Coach inference fixture.

Steps:

- [ ] **Step 1: Write the failing UI test** `testCoachDeletedMealShowsUndoAndRestores`.
  - A fixture reply calls `delete_meal` on a seeded meal.
  - Assert `app.buttons["coachUndo"]` exists, tap it, and assert the meal reappears on Today.
  - Add the fixture case to `CoachUITestInference.swift`, inside `#if DEBUG`.
- [ ] **Step 2: Run and confirm failure.**
- [ ] **Step 3: Implement** the filter change, and any card change the test shows is needed.
- [ ] **Step 4: Run and confirm pass.**
- [ ] **Step 5: Commit** `feat(coach): show Undo on delete receipts`

### Task 5: Visible delete button on food rows

**Files:**
- Modify: `ios/Mivu/Diary/MealDetailView.swift:263-290` (`foodRow`). Add a trailing button next to the Ask Pip button.
- Test: `ios/MivuUITests/DiaryUITests.swift`

Steps:

- [ ] **Step 1: Write the failing UI tests.**
  - `testFoodRowDeleteButtonRemovesOneFood`: a seeded meal with two foods. Tap `deleteFood` on the first row. The dialog title is `Delete <name>?`. Tap `confirmDeleteFood`. One food remains.
  - `testFoodRowDeleteOnLastFoodOffersDeleteMeal`: the dialog title starts with `Delete “`. Confirming dismisses meal detail.
- [ ] **Step 2: Run and confirm failure.**
- [ ] **Step 3: Implement.**
  - Show the button only when `meal.state == .saved`.
  - Label it `Image(systemName: "minus.circle")`, framed 44×44, with `.accessibilityLabel("Delete \(item.name)")` and `.accessibilityIdentifier("deleteFood")`.
  - Action: `deletion = meal.items.count > 1 ? .food(item, revision: meal.revision) : .meal`.
  - Keep the swipe action.
- [ ] **Step 4: Run and confirm pass.** Also run `DiaryUITests` swipe-delete tests to confirm there is no regression.
- [ ] **Step 5: Commit** `feat(diary): visible delete button on each food`

### Task 6: Verification and evidence

- [ ] Run `MivuTests` focused on `CoachDeleteUndoTests`, `CoachUndoTests`, `CoachEngineTests` and `DiaryArchive`-related suites, plus the two new UI tests and the swipe test, through XcodeBuildMCP. Record the SHA, the result bundle path and the counts in `docs/verification/2026-10-29-coach-delete-undo.md`.
- [ ] Run Ponytail Review on the branch diff and fix blocking findings.
- [ ] Commit `docs(verification): record coach delete undo evidence`
