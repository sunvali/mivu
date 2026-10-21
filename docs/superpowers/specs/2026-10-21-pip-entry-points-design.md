# Pip entry points: one way to log, one way to ask

Branch `feat/pip-entry-points` from main `dd5e8c34` (includes coach-context, #44).

## Why

Coach is the primary way to log and change records, and its swipe-to-reply
quote (`CoachReply`) is how a message points at a specific thing. Outside the
chat, Today, Diary and Progress still carry older paths: a "Log meal" button
that opens the legacy free-text `MealComposerView`, "Add note or photo" that
reuses that composer as a correction, and an "I ate half" button that posts a
hard-coded `"half"` correction. Users can't tell which buttons talk to Pip and
which are manual forms. After this change every button either opens Coach
(with a quote when it is about a record) or says "manually".

## Goals

1. **Log with Pip.** Today's primary `DiaryCaptureAction` ("Log meal") becomes
   "Log with Pip": switch to the Coach tab; the keyboard stays down until the person taps the field.
   On a Diary day (`logMealForDay`), the same, plus the composer starts a reply
   quoting that day (`CoachReply.Target.day`).
2. **Add manually** link beside that primary on Today and the Diary day: a
   secondary (non-prominent) button opening `ManualNutritionView` for that day
   (same as today's "Enter nutrition manually" in the Diary `+` menu).
3. **Meal detail**
   - Remove "I ate half" (`halfPortion`).
   - "Add note or photo" (list row `correctMeal` and the ⋯ menu item) opens
     Coach with a `.meal(mealID:)` reply showing above the field (keyboard down). Photos and
     camera come from Coach's composer.
   - Today's notification "add a note" sheet (`noteMealID`) does the same.
4. **Ask Pip with a quote everywhere a record is shown**
   - Meal and food Ask Pip: unchanged (already quote).
   - Diary-day Ask Pip: when the day is recorded, open with a `.day(dayID:)`
     reply. Unrecorded day: keep the current "For <date>: " starter draft
     (no record to quote).
   - Progress weight entries and workout sessions: add an Ask Pip action
     (swipe action / context menu, same affordance as foods in meal detail)
     that opens Coach with a new `.weight(weightID:)` or
     `.workout(workoutID:)` reply.
5. **Manual labels.** "Log morning weight"/"Morning weight" →
   "Add weight manually"; "Log workout" → "Add workout manually" (Progress and
   the Diary-day `+` menu). Sheet titles follow. Forms unchanged.

## Non-goals

- Ask Pip on Today's summary cards.
- Changing Coach's own empty-state chips or Coach-side reply UI.
- Changing store APIs (`correctMealProjection` and friends stay; tests use them).

## Anti-goals

- A button that says "Log" but silently opens a manual form, or one that talks
  to Pip without a visible quote when it is about a specific record.
- Losing a typed draft: opening Coach with a quote must follow coach-context's
  existing draft set-aside rules (`startReply`, navigation `draft`).

## Constraints

- Reuse `OpenDiaryCoachAction(target, draft:, reply:)` and
  `CoachViewModel.startReply`; no new navigation mechanism.
- New reply targets must be resolved in
  `DiaryDatabaseCoachContext.coachReplyContext` with a bounded read, marking
  `unavailable` when missing, and render in `CoachReplyQuote` (excerpt such as
  "Weight · 72.4 kg · Mon 19 Oct", "Workout · Strength 45 min · Mon 19 Oct").
  `CoachReply` is persisted with turns, so adding enum cases must keep older
  stored payloads decodable.
- English only, Dynamic Type, VoiceOver labels, 44-pt targets, reduced motion.
- Tests first: one focused unit test per new reply target (encode/decode and
  context resolution), UI tests updated for renamed/removed identifiers.

## Apple sample mode (owner decision)

Coach has no sample analyzer, and ~40 UI-test steps create meals through
`MealComposerView` via `logMeal`. Keep `MealComposerView` for sample mode
only: when `model.sampleMode` is true, the primary button and "Add note or
photo" keep opening the composer (sample banner stays). Real users never see
it. Existing sample-mode UI tests keep working; Coach handoffs get new focused
UI tests in non-sample mode. `shortcut:` comment on the branch — delete the
composer if sample mode is removed or Coach gains a sample analyzer.

## Settled after review

- **Coach offline / not connected:** "Log with Pip" still opens Coach; Coach
  already saves captures locally and shows its own blocked state. No extra
  availability checks on Today/Diary. (answered by existing behavior)
- **Unrecorded Diary day:** "Log with Pip" uses the same "For <date>: " starter
  draft as Ask Pip; no day-less reply target. (my call)
- **No automatic keyboard (owner):** no handoff opens the keyboard. Coach
  shows the quote or draft above the field and the person taps to type. This
  also removes the existing `editing = true` after `startReply` in
  `CoachView`'s navigation task.
- **New quote context depth:** carry the weight entry / workout session record
  in `CoachContext.Reply`, like `meal`, bounded by the same 8 KB check; update
  any model-facing text that enumerates target kinds. (my call)
- **Composer already has a draft or quote:** keep coach-context's rule that a
  handoff never replaces a started message; Coach still opens on the existing
  draft, so the tap is not silent. (my call)

## Left to the builder

- Exact placement/style of "Add manually" next to the primary button.
- Excerpt wording for the new quote kinds.
- How UI tests that ran in non-sample mode through `logMeal` adapt (switch to
  sample mode, or log via the Coach UI-test fixture).
