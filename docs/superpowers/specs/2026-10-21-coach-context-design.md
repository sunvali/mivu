# Coach context — design

Date: 21 October 2026. Base: `feat/coach-reply` (PR #39). That PR adds `CoachReply` and
`CoachContext.replyTo`, so this work lands after #39 merges.

## Why

The owner reports that Coach "is not managing the context in a smart way". These are real transcripts:

1. **Diary handoff.** The draft "About the Snickers Minis from Wed 21 Oct: I didn't eat them by the end" gets "Which meal do you mean?". The owner answers "Snickers mini" and gets the same question again.
2. **Correction right after a log.** Coach logs "Creamy salmon pasta + green beans, 845 kcal" and shows the saved card. "I think it should be around 650" gets "Which meal do you mean?".
3. **Photo log.** The almonds photo is logged and its card is shown, then a red "Analysis could not finish" appears.

The person expects the behavior of a good human assistant: "it" means the thing we were just talking
about, and a question is asked at most once.

## Root causes (from `CoachEngine`, `DiaryDatabaseCoachContext`, `CoachTools`)

- **History is not chat history.**
  - Earlier turns reach the model only inside the context JSON, as `recentTurns`: 12 entries, 1 KB of text each. Each entry has the user's text and the rendered assistant sentence.
  - The entries carry no meal or item IDs, no tool calls, and no receipts.
  - The model has to match "it" by name against up to 40 meals.
- **No current subject.**
  - Nothing tells the model what was last changed.
  - Nothing tells it that a question is pending, or that a message answers that question.
- **The prompt pushes the model to ask.** The developer prompt says:
  - "Omitted or paginated evidence cannot establish uniqueness; ask a focused clarification."
  - "Ask when the matching food or serving is ambiguous."

  The context is often truncated, so uniqueness can never be established.
- **Clarification is one generic sentence per kind.**
  - The `meal` kind always says "Which meal do you mean?".
  - That includes the case where `delete_item` says to confirm deleting the whole meal (the Snickers case).
  - The answer is not tied back to the question.
- **No meal-level total.**
  - "Around 650" for a two-food meal has no tool. `correct_item` changes the quantity of one item.
- **A clarification after a write fails the turn.**
  - `CoachEngine.swift:86` rejects `ask_clarification` once the turn has receipts.
  - The turn then shows the generic failure even though food was saved. This is the likely cause of the almonds failure, but it is inferred, not confirmed from diagnostics.
- **Cache-hostile layout.**
  - The per-turn context JSON sits inside the first developer message.
  - The prompt prefix therefore changes on every request, and prompt caching never applies.

## Decisions (owner chose each, 21 Oct)

1. **Turns plus a focus block.**
   - **Recent exchanges as real messages.** The last ~12 exchanges are sent as `user` and `assistant` messages, not as JSON. Each assistant message ends with a compact receipt line that has real IDs, for example:

     `[saved: meal 4F… "Creamy salmon pasta", "Green beans" 845 kcal on 2026-10-20]`

     Clarification questions are included as asked.
   - **History stays on the phone.** Keep `store: false`. Do not use server-side conversation state.
   - **A per-turn `focus` object** is resolved from local data. It contains:
     - `replyTo` (from #39): a quote or Diary handoff with meal and item IDs.
     - `lastChanged`: the meal or item touched by the most recent committed Coach or manual write, with its ID, name, date and revision.
     - `pendingQuestion`: the original request text, the question asked, and the candidate IDs, when the previous Coach turn ended by asking.
   - **Cache-friendly layout.** Order the input as:
     1. stable developer rules
     2. tools
     3. history
     4. a second developer message with the context JSON and focus
     5. the current user message

     Today's date stays out of the stable prefix.
2. **Act, say it, offer Undo.**
   - **Resolution order:**
     1. explicit mention
     2. `replyTo`
     3. `pendingQuestion` answer
     4. `lastChanged`
     5. newest matching meal
   - **When one referent wins,** Coach performs the edit and names it in the reply, e.g. "Updated salmon pasta to ~650 kcal".
   - **Coach asks only when:**
     - two candidates genuinely tie, or
     - the action deletes a whole meal (the owner's earlier rule: Pip asks before deleting the last food).
   - **The prompt is rewritten** so that truncation alone is not a reason to ask. The model can use `get_meals_for_date` or `find_meals` instead.
3. **Tappable clarifications.**
   - `ask_clarification` gains optional `candidates`: up to 4 real meal or item IDs, plus a `confirm` kind for "Remove the whole Snickers meal?".
   - The app renders the candidates from the local Diary as chips showing a thumbnail, the name and the time. `confirm` shows two buttons.
   - **Tapping a chip** sends a turn that replies to that candidate (a `CoachReply` target), with `pendingQuestion` carrying the original request. Coach then completes the original request.
   - **A typed answer** carries `pendingQuestion` as well.
   - **The same question is never asked twice in a row.** If the model asks again with the same kind and candidates, the app shows the chips again rather than a new generic sentence.
4. **"Around 650" scales portions.**
   - A new write tool, `scale_meal(meal_id, expected_revision, target_kcal)`, scales every item's quantity by the same ratio.
   - Nutrition stays on each item's basis. The receipt reports the old and new totals.
   - Manual parity: the meal detail sheet gets the same action, behind the existing edit affordances (builder's call where).
5. **Undo on the receipt card.**
   - Every Coach food write shows Undo on its card.
   - Undo restores the prior state with a revision check, and it stays available until a later write changes that meal (revision mismatch hides it).
   - Undoing a `log_food` deletes that meal.
   - "Undo that" in chat works through an `undo_change(receipt_id)` tool. Coach-edit parity applies.
6. **Show what saved.**
   - If the turn committed any receipt, a later failure or clarification never shows the red failure.
   - The turn shows its saved cards. A failure is followed by a quiet line, "Couldn't finish the rest · Retry"; a clarification is shown as a normal question with chips.
   - `ask_clarification` after a write ends the turn gracefully instead of throwing.
7. **~12 turns plus lookup.**
   - Add a read tool, `find_meals(query, from_date?, to_date?)`. It returns at most 10 meals by name match, newest first, with IDs.
   - Older references ("the pizza last Tuesday") use it.
   - There is no rolling summary.

## Follow-up answers (owner, 21 Oct)

- **Undo scope: food only.** Undo covers changes to meals and foods: log, append, edit, correct, scale and delete.
  - Weight, workouts, goals, preferences, closing a day and photo edits keep today's behavior.
  - `undo_change` accepts only food receipts.
- **How long `lastChanged` lasts:** it holds only within the current waking day.
  - It counts food changes only, whether made by Coach or by hand.
  - After the day rolls over it is absent. A reference then needs a name, a reply quote or the Diary handoff.

## Builder-check calls (my calls, not the owner's; correct me)

- **Undo creates no chat exchange.** It is a direct Diary edit, recorded like a manual write with a revision check.
  - It does not count toward the 100-exchange window.
  - The receipt itself stays immutable. The card shows "Undone" from a separate undo record keyed by receipt ID.
  - Undo hides once the meal's revision differs from the receipt's resulting revision.
- **Reply text stays app-generated.** Turns with receipts keep the app-generated summary built from the receipts, so the guard against unbacked "saved" claims stays.
  - When the model chose the target itself (no explicit mention or reply), the summary names that target, e.g. "Updated salmon pasta: 845 → 650 kcal".
- **Clarification text is templated from the candidates, not written by the model.**
  - The `confirm` kind reads "Remove the whole <meal name> meal?".
  - Choice kinds read "Which one did you mean?".
- **Tapping Yes on `confirm` sends a reply turn** that targets the meal, with `pendingQuestion`. Coach then performs the delete with its revision check. No delete runs without the model.
- **The partial-failure Retry starts a new turn.** That turn replies to the failed turn, with the original request in `pendingQuestion`. Receipts already in history are never re-applied.
- **`scale_meal` rules:**
  - The ratio is target kcal divided by the current known kcal.
  - It refuses when known kcal is 0, the meal has an unaccepted review, or the ratio falls outside 0.1–3.
  - It scales every item's quantity, rounded to 2 decimals, fractional counts included, and accepts the small miss against the target.
  - The receipt states the new total.
- **History caps carry over:** 12 exchanges, 1 KB per text, 8 KB in total, now as messages instead of JSON.

## Non-goals

- Server-side history (the OpenAI Conversations API, `previous_response_id`).
- Rolling summaries or long-term memory.
- Voice input.
- Changes to the timeline UI beyond chips, Undo and the partial-success line.

## Anti-goals (a failure even if it works)

- **Silent edits.** Coach edits something without saying what it edited, or with no visible Undo.
- **Fewer questions about new food.** Asking less about genuinely missing food or portion on new intake. The existing portion and day rules stay.
- **More data sent.** Sending more personal data than today. The JSON caps stay; history moves out of the JSON, it is not added on top of it.
- **Re-applying changes.** Re-applying committed receipts on retry or recovery. The existing immutability rules stand.

## Constraints

- AGENTS.md Coach rules:
  - bounded owner queries
  - request-time capture of source and ownership
  - the 100-exchange window
  - immutable receipts
  - the floating Jump to latest stays untouched
- Swift 6, native SwiftUI, Precision Glass tokens, Dynamic Type, VoiceOver, 44-pt targets.
- Synthetic inputs only in tests. Every new write has a manual equivalent.

## Verification

- **Unit tests of request assembly:**
  - history becomes messages with receipt lines
  - the focus fields
  - the stable-prefix order
  - `pendingQuestion` round-trip
- **Unit tests of each new tool** (`scale_meal`, `undo_change`, `find_meals`, candidates and `confirm`), including stale revisions and replay.
- **UI tests with `CoachUITestInference`:**
  - chip tap resumes the original request
  - Undo on a receipt card
  - partial success shows saved cards with no red error
- **Model behavior check.** Live model behavior can't be unit-tested. A manual on-device pass replays the three transcripts above and records the result.

## Left to the builder

- Exact receipt-line format.
- Chip visuals within Precision Glass.
- Where `scale_meal` sits in the meal UI.
- How Undo stores the prior state (snapshot vs. inverse operation).
- Prompt wording within the decisions above.
