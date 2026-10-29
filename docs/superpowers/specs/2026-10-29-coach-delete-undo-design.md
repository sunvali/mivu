# Coach delete Undo and visible food delete — design

Date: 2026-10-29. Base: `main` @ `8dc3a327`. Branch: `feat/coach-delete-undo`.

## Why

A security audit (run-2, lead `mivu.ai.destructive-tools-unscoped-and-unconfirmed`) found that the Coach can delete a whole meal, a meal photo, a weight or a workout as soon as the model asks. The only guard is prompt text, so text injected into a photo, a meal name or a USDA result could steer the model into a deletion the owner never asked for. None of these deletes can be undone. Undoing a Coach-logged meal also deletes that meal for good.

The owner wants Mivu to stay AI-first: Coach actions should still be fast and not ask for confirmation. The fix is therefore **recoverability, not confirmation**. Every Coach delete gets an Undo.

Separately, deleting a single food in the diary today needs a hidden swipe. The owner wants a visible button.

## Goals

1. Every destructive Coach write can be undone from its receipt card, and by asking Pip. That covers `delete_meal`, `delete_photo`, `delete_weight` and `delete_workout`, plus `undo_change` of a `food/…` key, which deletes a whole Coach-logged meal.
2. The Undo window lasts **until the owner's next Coach message, or 10 minutes, whichever comes first**. Then Undo disappears and every byte held for it is erased.
3. Undo restores the full record: a meal comes back with its foods, day, eaten time, title, saved state and **photos**. Weights and workouts come back with all their fields.
4. While held for Undo, deleted data is invisible everywhere: Today, History, Progress, totals, the widget snapshot, Live Activity, Coach context, archive export, folder backup and report export.
5. In meal detail, each saved food row shows a visible delete control. Tapping it asks for confirmation and then deletes the food. On a meal's only food, the confirmation is the delete-meal confirmation.

## Non-goals

- No confirmation step for Coach deletes. The owner explicitly chose Undo over asking.
- No change to manual (non-Coach) deletes. They keep their existing confirmation dialogs and stay permanent.
- No Undo for single-food Coach deletes beyond what exists. `delete_item` already has Undo.
- No fix for the Siri locked-intent lead in this change.
- No general trash or recently-deleted screen.

## Anti-goals (failure even if it "works")

- A held deletion reappears in a backup, an export, a total or Coach context.
- Undo resurrects a tombstoned ID. Backups enforce "tombstones only grow", so restoring the old ID would stall the folder backup with `staleArchive` and break the rule "never restore stale data over deletions" (AGENTS.md).
- Held photo bytes outlive the Undo window, for example after an app kill, a relaunch or a profile deletion.
- Undo silently overwrites something the owner changed after the delete.
- Any change to receipt immutability. Receipts are never edited. Undo state stays derived, as it is today with `coach_undo`.

## Decided by the owner

- Use Undo instead of a confirmation question for Coach deletes.
- Coverage is all destructive Coach writes, as listed in goal 1.
- Window: until the next message, or about 10 minutes.
- Photos come back on Undo, held hidden until the window ends.
- Pip may undo by voice: `undo_change` accepts these delete keys.
- A visible delete button sits on each food row. On the last food it offers "Delete meal".

## Constraints (from the codebase and AGENTS.md)

- Native Swift, platform APIs first, Ponytail minimal style. Write a failing test first. Run focused tests with XcodeBuildMCP, and record the source SHA and result bundle.
- Keep the existing layers. `DiaryTransaction` mutations sit in `DiaryDatabase*Mutations.swift`. `DiaryStore` wraps transactions with owner, profile and quota checks. `CoachViewModel` drives receipt Undo (`undo`, `undoStates`, `CoachReceiptView` `CoachUndoState`).
- `coach_undo` is derived and never archived (`DiaryDatabase.swift:57`). The archive, folder backup and report code never read it. Undo payloads must live in that table, or in a sibling derived table created the same `IF NOT EXISTS` way, so they are excluded from export by construction.
- `deleteMeal` (`DiaryDatabaseMealMutations.swift:622`) writes a meal tombstone and removes photos, items and submissions. Weight and workout deletes write `weight_tombstone` and `workout_tombstone`. Undo must therefore **recreate under new IDs** using the existing creators: `insertMeal`, `insertPhoto(_:owner:)`, item saving, `createWorkout`, `setWeight`.
- The diary DB file size is quota-checked (`maximumBytes`). Held photo bytes count toward it while held. That is acceptable because the window is short.
- Accessibility: Dynamic Type, VoiceOver labels, minimum 44-point targets, reduced motion. The UI is English only.
- Every manual edit must also work through the Coach (memory: Coach edit parity). Deleting a food is already possible through the Coach (`delete_item`). The row button reuses the manual store paths.

## How it works (decided)

- **Snapshot before delete.** In the same transaction as each destructive Coach write, capture everything Undo needs and store it in derived storage keyed by the write's `operationKey`:
  - For a meal: the record, items, photo metadata and bytes, and the day it belongs to.
  - For a weight or a workout: the record.
- **Expiry.** A held snapshot expires when either of these happens first:
  - the owner captures a newer Coach turn in the same profile;
  - 10 minutes pass since the write.

  An expired snapshot is purged: its row and bytes are deleted. Purge runs on the next capture and on app start, and lazily wherever Undo availability is read. The receipt shows no Undo once the snapshot has expired.
- **Undo.** Recreate the record under new IDs, re-attach the photos, and mark the undo row undone. If the day the item belonged to no longer exists, recreate it the way Coach writes do (`coachDay`/`resolveDay`) *(builder may choose)*.
- **Model tool.** `undo_change` key validation (`CoachManualEdits.swift:207-211`) accepts `delete_meal/`, `delete_photo/`, `delete_weight/` and `delete_workout/` keys, in addition to today's food keys.
- **Receipt Undo button.** It currently shows only for receipts with `mealID`. Extend it to delete receipts: weight and workout deletes carry `weightID`/`workoutID`, and photo deletes carry `mealID`. The undone state shows as it does today.
- **Food row button.**
  - Each saved food row in `MealDetailView` gets a visible trailing button (a minus or trash symbol, 44 points, VoiceOver label "Delete <food name>").
  - It sets the existing `deletion` state: `.food(item, revision:)` when the meal has several foods, `.meal` when it has one.
  - The existing confirmation dialog and `deleteFood`/`deleteMeal` paths handle the rest. The swipe action stays.

## Calls made after review (designer's calls, not the owner's)

These are the designer's own choices, made after the reviewer's questions. The owner did not make them.

1. **Expiry and voice Undo.**
   - The receipt **button** shows only while no newer turn exists in the profile.
   - The **snapshot** survives one more turn, so "undo that" in the very next message works through `undo_change`.
   - Capturing a turn purges every snapshot older than the previous turn.
   - Separately, any snapshot older than 10 minutes is unavailable and purged. This uses the wall clock, so it also applies after a relaunch.
2. **What a restored meal contains.**
   - It gets its record fields (day, eaten time, title, saved state), its items and its photos under new IDs.
   - Submissions and capture links are history and are not restored.
   - Old receipts keep the old ID, because receipts are immutable.
   - The derived row stores `restoredID` so the card shows "Undone".
   - The undo's own receipt `resultJSON` carries the new meal ID, as the existing undo already does, so the model can address the restored meal.
3. **Undoing a Coach-logged meal.**
   - Before `undo_change` of a `food/…` key deletes a whole meal, it takes the same snapshot as `delete_meal`, through one shared helper that wraps both delete sites.
   - That undo's own receipt can therefore be undone, which recreates the meal.
   - `undo_change` accepts that receipt's key kind as well.
4. **Conflicts on restore.** Undo never overwrites anything:
   - **Meal:** always recreated. If its day is gone, the day is re-resolved the way Coach writes do.
   - **Photo:** re-attached when the original meal still exists, whatever its revision, because adding a photo overwrites nothing. If the meal is gone, the undo is refused (`notFound`).
   - **Weight:** refused (`staleRevision`) if that day already has a weight.
   - **Workout:** always recreated, since several per day are allowed.
5. **Quota.** If taking the snapshot would exceed the diary size limit, the delete still happens with no Undo, and the receipt shows no Undo. Coach deletes are never blocked by Undo bookkeeping.
6. **The model knows.**
   - Each delete's tool result includes `undo_key` (the receipt's `operationKey`) and `undo_until: "next message"`.
   - Snapshot storage is a **sibling derived table**, for example `coach_undo_deleted` with `operationKey`, `turnID`, `kind`, `payload`, `createdAt`, `restoredID` and `undone`. It is created `IF NOT EXISTS` and cascades on `coach_turn`.
   - Using a sibling table means `coach_undo.mealID` stays `NOT NULL`.
7. **Profile deletion.** Each profile's diary is its own SQLite file, which is removed on profile deletion, so held bytes go with it. One test asserts this.
8. **Food-row button.** It is manual only. It uses the existing manual delete paths and confirmation, and it has no Undo, consistent with the non-goals.

## Left to the builder

- The exact snapshot storage shape: new columns on `coach_undo`, or a sibling derived table. It must be created with `IF NOT EXISTS`, with cascade on `coach_turn` deletion and on profile deletion.
- How the 10-minute clock is stored, whether as a capture timestamp on the row or derived from the turn.
- Whether photo undo for a meal that still exists re-attaches the photo to the same meal (the expected behaviour) and how photo consumers are rebuilt.
- The SF Symbol choice and exact placement of the row button, following Apple HIG and the existing row layout.
- Test names and fixtures. Use synthetic data only, and keep focused tests in `ios/MivuTests`. A UI test covers the row button and dialog.

## Acceptance

- Unit tests, each failing before the change:
  - For each destructive Coach write: Undo is available, then Undo restores the record with equal content under a new ID, photos included, and the tombstone stays.
  - A newer capture, or more than 10 minutes, makes Undo unavailable and purges the held bytes.
  - Held data is absent from the archive snapshot and from day totals.
  - `undo_change` accepts the new key kinds and rejects unknown ones.
- UI test: tapping the food-row button shows "Delete <name>?", and confirming removes the food. For a single-food meal it shows the meal confirmation.
- Focused `MivuTests` and the affected `MivuUITests` pass locally through XcodeBuildMCP. Evidence records the exact source SHA.
- Ponytail Review has no blocking findings.
