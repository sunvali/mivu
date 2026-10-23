# Coach replies that read like a coach

## Why

Coach replies currently read like a database dump. Asking "I weighed 73.6 kg
this morning. How am I doing?" returns twenty lines such as "Remaining carbs
from recorded food: 39.5 g", "Day coverage: unknown; pending: false" and
"Observed plateau readiness: insufficientData."

The cause is in `CoachEngine.run`. When the model finishes, the app throws away
its prose (`response.text`) and substitutes deterministic summaries:
`coachCommittedSummary` when something was saved, `coachRecordedSummary`
otherwise, plus `coachProgressSummary`, `coachWorkoutSummary`,
`coachGoalSummary` and `coachPreferenceSummary` for each read tool the model
called. Those summaries were written to stop the model inventing numbers or
claiming saves. That goal stays. Throwing away all prose was too blunt.

The owner wants replies that feel integrated with the app's existing design:
short, warm, and backed by native cards in the same visual language as Today.

## Goals

- Pip's own reply: 2–3 warm, brief sentences that answer the question first,
  with at most one suggested next step.
- Every save in the turn appears as a native card inside the same message.
- A big multi-dish photo meal is one message: one sentence, one meal card
  listing every dish.
- Numbers in prose are never invented.

## Non-goals

- Diet-aware notes (gluten-free warnings, carb counts for type 1 diabetes).
  A later feature; it will add a line to the meal card. Nothing is built for it
  now.
- Streaming, a new response schema, or a second summarising model call.
- Changes to clarification questions. They stay app-owned (`kind.question`).
- Model-generated follow-up suggestions.

## Anti-goals

- A reply that states a number the diary or retrieved facts do not support.
- A reply that says something was logged or saved when no matching receipt
  exists, or when the meal is only awaiting review.
- A second "current state" block that duplicates the receipt (forbidden by the
  behavior contract).
- Any regression in Dynamic Type, VoiceOver, Reduce Motion or 44-point targets.

## The message

One exchange row shows, in order: the user's input bubble (unchanged, photos
included), Pip's reply text, the cards for this turn's receipts, then follow-up
chips.

### Reply text

- Comes from the model's final `response.text` whenever it passes the checks
  below.
- Inline Markdown only: bold is allowed (the prompt asks for at most one bold
  key number). Render with
  `AttributedString(markdown:options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))`;
  if parsing fails, show the plain string.
- Any surface that shows the reply as plain text strips the Markdown. Today
  that is only the text itself. The planned Siri reply notification
  (`docs/superpowers/plans/2026-10-23-siri-coach.md`, Task 5) must use the
  stripped form, and that plan gets a one-line note saying so.
- The stored `assistantText` keeps the Markdown. The 64 KB limit is unchanged.

### Style instruction

Append one short style paragraph to the existing developer message in
`CoachEngine`:

> Reply to the user in at most three short sentences. Answer their question
> first. Be warm and encouraging without filler. Offer at most one next step.
> Use bold for at most one key number. No headings, lists or tables. Round
> calories to the nearest 10. Do not mention data that is unknown, missing or
> zero unless the user asked about it. Never state a number you did not read
> from the context or a tool result in this turn.

### Honesty check

A small pure function, `CoachReplyCheck`, decides whether the model's prose is
shown. It lives on its own (no store or UI dependency) so a later server worker
can reuse it.

Inputs: the prose, the set of allowed numbers, and the turn's committed
receipts.

Allowed numbers are every number appearing in the developer context JSON, every
tool output string returned in any iteration of this turn (the engine
accumulates them across the whole loop, not just the last iteration), and every
receipt's item quantities and nutrition. Each allowed number also allows its
rounding to the nearest 1 and nearest 10, and its value with grouping
separators ("1,240" equals 1240). The only derived values added are
per-receipt summed kcal/carbs/protein/fat. Other derived values (an average or
difference the model computes itself) are not allowed unless they appear
verbatim in a tool output. `get_progress` JSON already carries remaining
amounts, averages and weight changes, so normal progress prose passes.

The prose fails if any of the following is true:
1. It contains a number not in the allowed set. Dates in `YYYY-MM-DD` form
   and clock times are allowed when they appear in the context or tool output.
2. It claims a save and the turn has no receipt. This is today's
   `ungroundedConfirmation` check, kept exactly: the same action list
   ("saved", "logged", "recorded", "updated", "deleted", "closed", "added")
   after the same subjects ("i ", "i've ", "i have ", "we ", "we've ",
   "we have "). It still throws. The check stays turn-level, not per record
   kind (a kind-aware classifier is out of scope).
3. A meal receipt in the turn is `.awaitingReview` and the prose contains
   "logged" or "saved" anywhere (no subject required).
4. It is empty after trimming.

Failure of rule 1, 3 or 4 does not fail the turn. The reply falls back to the
template line (turns with receipts) or the fact line (read-only turns).

### Template line (fallback and recovery)

One short sentence built by the app from receipts, never from current-state
facts:

- Meal saved: "Saved — about **{kcal rounded to 10}** kcal." or "Saved." if kcal
  is unknown.
- Meal awaiting review: "Your estimate is ready for review."
- Weight: "Weight saved: **{value} {unit}**."
- Workout: "Workout saved: {kind}, {minutes} minutes."
- Goals: "Your goals are updated."
- Preferences: "Your preferences are updated."
- Several receipts: the line for the first receipt in `turn.receipts` order,
  plus "Everything is in the cards below." when more than one card is shown.

The workout line needs kind and minutes from the committed result. The workout
receipt's `resultJSON` is the saved `WorkoutSession`, so `ReceiptFacts` gains
optional `kind` and `durationMinutes`, and `CoachCommittedReceipt` gains
optional `workoutKind` and `workoutMinutes`, in the same way as weight below.
Legacy receipts that do not decode fall back to "Workout saved."

The template is built in `coachReceiptSummary`, which already produces one
sentence per receipt. Its meal, weight and workout sentences are replaced by
the lines above. The existing special-case sentences ("This meal was
deleted…", "Queued the original saved meal input…", "Photos attached…",
"Deleted the requested meal photo…", "Use the Settings link…") stay; they are
already short.

The crash-recovery path (`DiaryStore.setCoachTurnState(.completed)`) only
re-reads the stored `assistantText`. It is unchanged. A turn that completes
through recovery shows whatever text was stored, and its cards.

### Fact line (read-only fallback, owner's choice)

When a read-only turn's prose fails the check, the app writes one sentence per
read the model made, from the same data the model read, at most two sentences:

- Progress (single day): "Today: {food kcal} of {target kcal} kcal, about
  {remaining, rounded to 10} left." Parts with unknown values are dropped; if
  nothing is known, "There's no food recorded for {date} yet."
- Progress (multi-day): "Last {n} days: about {average kcal} kcal a day on
  {known days} tracked days."
- Weight in progress: appended only when the 7-day average is known:
  "Weight average {kg} kg."
- Goals: "Goal: {kcal} kcal a day." plus protein when set.
- Preferences: "Your preferences are up to date."
- Workout: "{kind}, {minutes} minutes on {date}."
- No reads at all: "I couldn't find anything to add there."

These replace `coachProgressSummary`, `coachWorkoutSummary`,
`coachGoalSummary`, `coachPreferenceSummary` and `coachRecordedSummary` as
user-facing text. Delete those functions if nothing else uses them.

## Cards

All cards use the Today visual language: `diarySummaryCard()` surface (24-point
radius, soft shadow, hairline rule), `Color.diary*` tokens, macro colours
`diaryProtein`/`diaryCarbs`/`diaryFat`, capsule accents as in
`NutritionSummary`. They are restyled `CoachReceiptView`, not `MealRow`:
`MealRow` shows the current record, and the contract requires the immutable
committed receipt.

### Meal card

Built from `CoachCommittedReceipt` (immutable), with current-record notices from
`CoachReceiptPresentation` unchanged.

- Header row: status title ("Saved" / "Awaiting review", coloured with
  `SubmissionState.color`), the receipt date, and the existing Review / Edit
  button (44-point minimum).
- Energy line: total kcal, large and monospaced, with an "Estimated" tag when
  `estimateLabel` is non-nil.
- Macro bar: one always-visible horizontal bar split by carbs/protein/fat
  energy share, in the macro colours, with a grams legend underneath. Hidden
  when any macro total is unknown (the "Some nutrients unknown" label shows
  instead).
- Dish rows: every committed item, no collapsing. Each row: name, quantity and
  unit, and the item's kcal on the trailing edge ("—" when unknown).
- Gram-level per-item macros remain behind the existing native disclosure.
- Existing notices (edited, moved, unavailable, needs review) keep their
  position and wording.
- No photo thumbnail: the photo is already in the user's bubble above.
- Accessibility: at accessibility sizes, rows stack vertically. Each dish row
  is one VoiceOver element reading "{name}, {quantity} {unit}, {kcal}
  calories". The macro bar reads "Carbs {g} grams, protein {g} grams, fat {g}
  grams". Identifiers from today (`coachReceipt-*`, `coachReceiptQuantity`,
  `coachReceiptNutrition`, `coachReceiptMacros`, `coachReceiptUnknown`,
  `coachReceiptChange`, `coachReceiptTargetStatus`, `coachReceiptDate`) are kept
  on the equivalent elements.

### Workout card

Today's receipt treatment, restyled to the same surface. No content change.

### Weight chip (new)

Receipts with a `weightID` currently render nothing. Add a compact capsule:
checkmark, "Weight saved · {value} {unit}", in `diaryWeight`. Value and unit
come from the receipt's committed result, not the current record:
`ReceiptFacts` gains optional `value` and `unit`, and `CoachCommittedReceipt`
gains optional `weightValue` and `weightUnit`. If the weight was later deleted
or changed, the chip shows the original value with the existing style of change
notice. Tapping does nothing in this change (no weight detail screen exists).

## Follow-up chips

App-chosen by turn content, at most two, rendered as small bordered buttons with
a 44-point minimum, below the cards:

- A meal receipt: "See today" (opens the Today tab).
- A weight receipt: "See progress" (opens the Progress tab).
- A read-only progress turn: "See progress".
- Otherwise: none.

Chips are derived at render time from receipts. For the read-only progress case
the engine cannot tell at render time which tools ran, so that chip is shown
only when the turn is completed, has no receipts, and its text came from a
progress read; the simplest route is to skip the read-only chip if detecting it
needs new stored state. Nothing new is stored. Only the latest exchange shows
chips, and only once it is `.completed`.

Tab switching already exists: `DiaryRootView` owns `selectedTab` and passes
closures such as `openDiary: { selectedTab = "diary" }` to child views. Coach
receives `openToday` and `openProgress` closures the same way.

## Behavior contract changes

Update `docs/development/coach-chat-behavior.md`:

- "Secondary macros sit behind a native disclosure" becomes: the meal receipt
  shows a visible macro split; per-item gram details sit behind a native
  disclosure.
- "Read-only summaries come from current diary reads; assistant prose alone
  cannot claim a saved record" becomes: assistant prose is shown only when every
  number in it is grounded in this turn's context, tool output or receipts, and
  it never claims a save without a matching saved receipt; otherwise a short
  app-written line is shown. Saved facts are always displayed by receipts.

## Tests

Write each failing test before its implementation.

- `CoachReplyCheck` unit tests: grounded prose passes; an invented number fails;
  "1,240" and a rounded "460" match 1240 and 458; a save claim without a
  receipt fails; "logged" with an awaiting-review receipt fails.
- Engine: a progress question with grounded prose stores that prose, not the
  fact list. Invented-number prose stores the template line.
- Engine: a multi-dish photo turn produces one exchange with one meal receipt
  holding every item.
- Weight receipt carries `weightValue`/`weightUnit`; the chip renders it.
- Receipt presentation: macro split and per-row kcal.

Existing tests: 91 assertions read `assistantText` across 19 files. Those that
assert true facts appear in the reply (dates, "3 piece", "420", "70 kg") and
invented ones do not ("9999") are rewritten to assert the same facts on the
receipt and that invented numbers never reach `assistantText`. Assertions about
`nil` text, clarification questions and timeline identity are unchanged.
`CoachUITests` lines 198–229 move their fact checks from the reply text to the
cards. The UI-test inference fixture's final text "Fixture finished." becomes
short synthetic prose that passes the check.

Run focused unit and UI tests with XcodeBuildMCP and record the source SHA.

## Left to the builder

- Exact spacing, the macro bar's height and legend layout, within Today's
  visual language.
- Where `CoachReplyCheck` and the template builder live (Analysis or Coach), as
  long as they stay independent of the store and UI.
- Number tokenising details beyond the rules above.

## Calls made without the owner

- No photo on the meal card (it is in the bubble).
- Weight chip has no tap action.
- Follow-up chip set and labels.
- Template wording.
- Rounding allowance of 1 and 10.
- Save-claim check stays turn-level, with today's word lists.
- Multi-receipt fallback follows receipt order.
- Workout receipts gain kind and minutes the same way weight does.
- Read-only progress chip may be dropped if it needs stored state.
