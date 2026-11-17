# Coach quick prompts: design

Date: 2026-11-17. Status: approved by the owner on 2026-11-17 (look: mockup round 4).
Base: branch `feat/coach-quick-prompts`, cut from PR #145 (`fix/coach-stale-photo-question`),
which the owner is about to merge. Rebase onto `main` once #145 lands.

Mockup: [assets/2026-11-17-coach-quick-prompts-mockup.html](assets/2026-11-17-coach-quick-prompts-mockup.html)
(it has a light/dark toggle) and a static capture
[assets/2026-11-17-coach-quick-prompts-mockup.png](assets/2026-11-17-coach-quick-prompts-mockup.png).

## Intent

Make the Coach chat faster and easier to use with a row of quick-prompt chips that suits
the moment. The owner wants all four of these benefits:

- **Faster logging.** Re-log a usual or recent meal in one or two taps.
- **Discovery.** New users see what Coach can do without facing an empty box.
- **Easier follow-ups.** After Coach logs something, the obvious next steps are one tap away.
- **Quick questions.** "Calories left?" and "Protein ideas?" take one tap.

The owner's bar is Apple/Airbnb polish. The row must keep Mivu's precision-glass look and must not
make the screen feel crowded. An independent UX/UI reviewer who specializes in AI-tool
experiences stays in the loop. That reviewer has already judged two mockup rounds, and must see
the real screenshots before the PR.

## What exists today (on the #145 base)

- `CoachView.swift` has `starters` / `showsStarters`: three fixed glass chips above the composer
  ("Log breakfast", "Log my weight", "How am I doing today?"). They show only when the timeline is
  empty, they fill the draft, and they never send. Their identifier is `coachStarter`. **This feature replaces them.**
- `coachFollowUp-today/progress/day` chips ("See today", "See progress", "See {date}") sit under
  replies (`CoachReplyLines.followUps`). **"See today" and "See progress" are removed** (decision 14);
  "See {date}" stays.
- PR #145 adds `optionChips`: answer options under a reply when Pip asks about an unclear food,
  plus "Something else? Type it". `CoachQuestionChips` covers candidate-meal clarifications.
  These answer chips belong to the turn and stay unchanged.
- `MorningCheckInCard` already pre-fills "My weight this morning is ".
- Pip sits above the composer and shows a short contextual line (`PipLine.current(hour:mealsLogged:…)`).

## Owner decisions

1. **Placement: one horizontal chip row inside the composer's glass tray** (mockup option A),
   above the text field. Option B, a row floating above the tray, was rejected.
2. **Visibility: the row shows whenever the text box is empty**, both with the keyboard down and
   with it up, in any conversation (not only an empty one). It hides at the first typed
   character, while voice is recording, or once a photo is attached.
3. **Tap behaviour depends on the chip type:**
   - **Send chips** ask a read-only question and send immediately. They never change the diary.
     They are marked by a trailing filled accent ↑ disc that echoes the send button.
   - **Fill chips** put text in the box, place the caret at the end, open the keyboard, and send
     nothing. They are used for everything that changes the diary: logging, re-logging and edits.
     A trailing "…" in the label means the user is expected to finish the sentence ("Log dinner…").
4. **Personalisation is context-aware and rule-based. The AI does not choose chips.** The inputs are
   the time of day, what is already logged today, targets left, and the kind of the latest Coach
   reply. AI-written follow-ups stay a non-goal, as the coach-reply spec already says.
5. **Follow-ups come from app rules by reply type** and are shown in the same row. They are not
   shown in-thread.
6. **The re-log chip mixes two sources.** It uses yesterday's meal in the same slot, and falls back
   to the user's most frequent meal in that slot over the last 14 days.
7. **The re-log chip is a "rich" chip.** It has a 30 pt round thumbnail and the meal's kcal, and
   its label names the meal, e.g. "Usual dinner · 540". The thumbnail is the meal's photo, cropped
   round, when one exists, and otherwise the `fork.knife` SF Symbol in the accent colour on a tint
   disc. **Emoji are never used.** The chip has a 9% accent tint fill and no border. Its kcal is
   13 pt, secondary colour, regular weight, with tabular digits.
8. **Pip's bubble stays but is kept short.** It is a mood line of three words or fewer that never
   repeats the reply or the chips ("Morning!", "Lunch is in!", "Dinner time?").
9. **Hiding:** long-pressing a chip offers "Hide this suggestion", and a single "Show suggestions"
   switch in settings turns the whole row off.
10. **Devices:**
    - On iPhone and on the upright Duo inner display, the row works as on iPhone.
    - On the **closed iPhone Duo** (outer display, 466×678 pt, system bar on the right), the row
      shows **at most 2 chips**, Pip stays visible but small (about 56–66 pt) even while typing,
      the large title becomes inline, and today's kcal moves into the title row in place of the
      date line.
    - On the **open Duo held sideways** (951×669 pt), the row belongs to the Coach column, never
      crosses the fold, and shows **2 chips**. "Calories left?" is replaced by "Was it balanced?",
      because the Today panel already shows the number.
11. **Scope: iOS (iPhone and Duo) now.** Android follows later as its own project with its own
    copies, under the decoupling rule.
12. The owner approved the chip catalog below.
13. **Re-log copies the meal exactly, through Coach.**
    - The fill text lists the source meal's foods **with amounts**, e.g. "For dinner I had grilled
      chicken 150 g, rice 1 cup, salad".
    - The draft also carries a reference to the source meal, captured at tap time, so Coach logs
      the same items and nutrition as the source. This means the logged kcal matches the chip
      (540). The new entry goes into the current slot, eaten now.
    - If the user edits the text before sending, Coach starts from the source items and applies
      the edits.
    - The copy uses Coach's normal log path, with a receipt, Undo and edit, so Coach parity holds.
      The exact mechanism is the builder's choice, for example a small new tool or a field on
      `log_food` that names the source meal. It is a small Coach change that is in scope.
    - If the source meal is gone or changed by send time, Coach falls back to estimating from the
      text and says so.
14. **Remove the "See today" and "See progress" follow-up chips** under replies, because the
    quick-prompt row replaces them. This means:
    - Drop the `.today` and `.progress` cases from `CoachReplyLines.FollowUp` / `followUps`, and
      their titles, identifiers and open paths.
    - Remove the sideways-Duo `.progress` pane if nothing else opens it.
    - Update the tests that use `coachFollowUp-today` / `coachFollowUp-progress`, in
      `CoachUITests` and `DuoLayoutUITests`.
    - **Keep "See {date}"** (`.day`), which opens a past day that Coach read and which no
      quick-prompt chip covers.
    - The Today and Progress tabs stay one tap away in the tab bar, and on the Duo, in the system
      bar.

## Chip catalog

The row shows at most 4 chips (2 on Duo, as above). Labels are **18 characters or fewer**. The
first two chips always include a send chip, so a question is never scrolled out of view. When no
rule produces a useful chip, **no row is shown**, and there is never filler.

**Meal slot by hour (local time; builder's call on exact boundaries):** breakfast before 11:00,
lunch 11:00–16:00, dinner after 16:00. A slot counts as already logged when today has a meal
whose `eatenAt` falls inside it.

| Moment | Chips, in order |
|---|---|
| Slot not yet logged | Rich re-log (if a source meal exists) · a send question for the moment · "Log {slot}…" · "Log weight…" (only with no weigh-in today **and** no morning check-in card showing) |
| Morning send question | "How was yesterday?" ↑ |
| Evening with protein below about 70% of target (builder's call on threshold) | "Protein ideas?" ↑ |
| Otherwise, with a kcal target | "Calories left?" ↑ |
| Latest reply logged a meal | "Calories left?" ↑ · "Smaller portion…" · "Add a drink…" |
| Latest reply logged a weight | "Weekly trend?" ↑ · then the slot chips |
| Latest reply logged a workout | "Calories left?" ↑ · then the slot chips |

The follow-up set applies until the user sends anything else. After that, the row goes back to the
time-of-day set.

**Fill texts:** fill chips produce plain sentences that Coach already understands, so every edit
still goes through Coach.

| Chip | Fills the box with |
|---|---|
| Log breakfast… | `For breakfast I had ` |
| Log weight… | `My weight this morning is ` (same as the morning card) |
| Rich re-log | `For dinner I had {foods with amounts}`, e.g. "For dinner I had grilled chicken 150 g, rice 1 cup, salad", plus the source-meal reference (decision 13) |
| Smaller portion… | `Make {meal name} a smaller portion: ` |
| Add a drink… | `Add a drink to {meal name}: ` |

Send chips send exactly their label as the message.

## Coexistence rules

- When the latest turn has an open clarification, meaning `CoachQuestionChips` candidates or
  #145's `optionChips`, the quick-prompt row is **hidden**. The answer chips own that moment.
  *(Builder's call; the owner can override.)*
- While a send is in flight, the row is hidden. It returns with the new set once the reply lands.
- The morning check-in card and the row can both show. The "Log weight…" chip yields to the card.
- Chips are recomputed when the screen appears, when the app returns to the foreground, when the
  hour changes, and whenever diary data changes. A chip must never point at a deleted or changed meal.

## Look and motion

- The chips sit **inside the existing composer glass tray**, in a single row with an 8 pt gap. They
  are 36 pt tall with a 44 pt hit target. The row scrolls sideways with a trailing fade of about
  24 pt and snaps so that no chip rests half-visible. The leading inset aligns with the text field.
- Plain chips use the surface fill with a hairline separator border, an SF Symbol at a single
  weight, 15–16 pt in the accent colour, and 14.5 pt medium text. Never put glass on glass:
  the tray is the only glass layer.
- On appear, the chips rise 6 pt and fade in over about 0.22 s with a 30 ms stagger. On the first
  keystroke they fade out over about 0.12 s. Under Reduce Motion they use a plain fade of about
  0.15 s.
- Haptics: a selection tick when a fill chip is tapped, and a light impact when a send chip is tapped.
- In dark mode, use the existing precision-glass dark tokens. The rich chip uses a 22%-strength
  tint in dark mode where needed for contrast.

## Accessibility

- Every target is at least 44 pt, and Dynamic Type scales the chips. At accessibility sizes the
  row stays one line and scrolls; above AX3, show at most 2 chips.
- VoiceOver gives each chip the button trait and a label plus hint, e.g. "Usual dinner, 540
  calories. Fills the message." and "Protein ideas? Sends to Coach."
- English only for the MVP. New strings go through `Localizable.xcstrings`, as the existing
  starters do.

## Goals, non-goals, anti-goals

- **Goals:** fewer taps to log repeat meals; a visible path to Coach's abilities; a one-tap next
  step after a log; a premium look on iPhone and on both Duo poses.
- **Non-goals:**
  - AI-generated chips.
  - Chips in Pip's bubble.
  - Chips pinned to receipt cards, which already have Undo and Edit.
  - Android, for now.
  - Any change to the "See {date}" follow-up or to the #145 answer chips.
  - Server-side work.
- **Anti-goals:** chips that change the diary without the user pressing Send; a cluttered bottom
  of the screen; stale chips; chips cut off mid-label on the device widths above; emoji or
  gradients that clash with precision glass.

## Builder's calls (made during brainstorming; the owner may override)

- Exact slot hour boundaries, and the protein threshold for "Protein ideas?".
- The 14-day window for "most frequent meal". A meal counts as "the same" when its food
  names, normalised, match.
- How "Usual {slot}" and "Same {slot}" labels are chosen: "Same {slot}" when the source is
  yesterday's meal, "Usual {slot}" when it is the most frequent one.
- Hiding the row while a clarification is open.
- **"Show suggestions" is a display preference, not diary data**, so it gets no Coach tool. The
  existing `open_settings` tool can take the user to it. (The Coach-parity rule covers diary edits.)
  The preference is stored with `@AppStorage`, like the other display preferences, and lives in
  the existing settings section next to the day settings.
- The chip-choosing logic is a small pure function, with inputs of now, today's meals, goals,
  the latest reply kind, the device layout, and hidden chips, so it can be unit tested without UI.

## Settled after the builder check (builder's calls)

- **Send chips are read-only by their wording.** No engine or tool restriction is added. Every send
  chip is a question about progress or ideas, and Coach already logs only on an explicit request.
  A unit test pins every send-chip label to the approved question list.
- **The slot is already logged and the latest reply is not a log:** the row shows the moment's
  question ↑ · "Log a snack…" · "Log weight…" (under the same weigh-in condition). It is never
  empty while a kcal target exists.
- **Follow-up lifetime:** a follow-up set shows only while the latest exchange is in the current
  waking day **and** its receipt's meal, weight or workout still exists unchanged. Otherwise the
  row shows the time-of-day set. Follow-ups are derived from the latest exchange the timeline
  already holds, with no extra history query, and never from yesterday's reply.
- **The meal named in "Smaller portion…" / "Add a drink…"** is the meal on the latest reply's last
  meal receipt. When that meal was deleted or changed, the follow-up set is dropped.
- **Re-log source when a slot had several meals:** the latest meal eaten in that slot.
  Meals with no food names are skipped.
- **Closed-Duo header changes apply to the Coach screen only.** The title-row kcal is the same
  "{eaten} of {target} kcal" text the Coach day line shows today. Other tabs are unchanged.

## Left to the builder

- Where the function lives, and how hidden chips are keyed. Hidden chips should survive
  relaunch and be cleared by turning the switch off and on.
- The thumbnail photo source and caching, reusing the existing meal photo loading.
- How the closed-Duo and open-sideways modes are detected, reusing `CoachViewportMode` and the
  existing Duo layout decisions.

## Verification (per AGENTS.md)

- Write failing unit tests first, in `ios/MivuTests`, for the chip-choosing function. Cover each
  slot, follow-up sets, the re-log source fallback, the no-row case, the Duo chip limits and the
  balanced-question swap, the 18-character limit, and the rule that a send chip is among the first two.
- Focused UI tests in `ios/MivuUITests`:
  - A fill chip fills the box and does not send.
  - A send chip sends.
  - The row hides on typing and returns when the box is cleared.
  - The row hides during a #145 clarification.
  - The row respects the long-press hide.
  - The settings switch works.
  - Update or replace the existing `coachStarter` assertions.
- Run the tests with XcodeBuildMCP, and record the source SHA. Run Duo checks on the Duo simulator
  in the closed, open-sideways and table poses with the on-screen keyboard. Run the
  `CoachNavigationUITests` that fail on Duo on a regular iPhone.
- Before the PR, give the independent UX/UI reviewer screenshots in light, dark and AX text on
  iPhone, closed Duo and open Duo, then run Ponytail Review.
