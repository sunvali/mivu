# Diary redesign

Date: 20 October 2026. Status: approved by the owner on 20 October 2026.

## Intent

The Diary tab, day screen and meal detail read like a settings form and do not
match Today. Editing a logged food is hard to find. Mivu is AI-first, so asking
Pip should be in reach everywhere. The owner wants the Diary to be easy to
read, eye-catching, minimal and high quality: a screen people want to open.

Success: a person finds any day in one or two taps, reads its intake at a
glance, and can change a logged food from where they see it, either by hand or
by asking Pip.

## Owner decisions

| Topic | Decision |
| --- | --- |
| Visual reference | Today: same summary card, `diarySummaryCard`, type scale, 20-pt inset, canvas, bottom bar |
| Scope | Diary tab, day content and meal detail. Today's own list is unchanged, but it reuses the shared `MealRow`, so its rows pick up the new look. Log meal composer and manual nutrition keep their sheets |
| Diary tab top | Swipeable week strip; the selected day's content shows inline below it (no push to a day screen) |
| Calendar | Keep a toolbar calendar button; choosing a date jumps the strip and selects that day |
| Add actions | Bottom bar like Today: **Log meal** plus a sparkle **Ask Pip**; a toolbar **+** menu holds manual nutrition, morning weight and workout |
| Coverage | A small status chip on the day summary; tapping opens a menu that sets Complete / Partial / Unknown / Untracked. Long explanation paragraphs removed (one short line stays in the menu) |
| Meal detail | Photo hero, large kcal + macro header, food rows you tap to edit; "Needs review" banner with its action; Move / Add note or photo / Retry / Delete meal stay in the `…` menu |
| Food edit sheet | Amount, unit, live kcal/macro preview, **Delete food**, and **Ask Pip to fix this**. Name and nutrient fields move under a collapsed "More details" (existing `FoodItemEditor` fields preserved, not removed) |
| Meal rows | Photo thumbnail (or meal icon), title, time, kcal on the right, thin protein/carbs/fat bar, "Needs review" dot |
| Delete single food | Included now, with manual and Coach parity |
| Empty date | "Nothing logged" empty state. Log meal works only when the date already has a recorded day; otherwise the bottom bar shows **Ask Pip** only (Coach can already log to a target date) |
| Ask Pip context | Opens Coach with the composer prefilled and unsent: "For Tuesday, 14 Oct: " for an empty date, "About the toast in Lunch: " from the food sheet. The person finishes and sends |
| Coach removes the last food | Pip asks whether to delete the whole meal; nothing changes until the person confirms |
| Review | Build in SwiftUI, then show light/dark simulator screenshots |

## Screens

**Diary tab.** Navigation title "Diary", calendar button leading, `+` menu and
profile trailing. Week strip: seven day pills (weekday letter, date number, a
small dot whose color shows that day's coverage, filled when the day has
records). Horizontal paging moves by week; today is marked. Below: the selected
day's summary card (kcal vs target if a goal exists, macro bars, coverage chip,
morning weight if any), then the meals as `MealRow` cards, then workouts if any.
The bottom bar is pinned to the bottom. The old Earlier/Newer/Latest buttons,
the date-filter section and the "Day coverage" disclosure are removed.

**Meal detail.** Pushed from a meal row as today. Top: first photo full-width
(tap opens the existing `MealPhotoViewer`); no photo → no hero. Header: title,
time, big kcal, macro bars. Review banner when the meal needs review, with the
existing Mark reviewed action next to the estimate label. Foods: one card row
each (name, amount + unit, kcal). Tap opens the edit sheet. "Record history"
stays as a collapsed disclosure at the bottom. Bottom bar: **Ask Pip** opens
Coach at the meal's source turn when it has one, else at its day. The existing
`openDiaryCoach` with `CoachSeekTarget` is used; no draft prefill.

**Food edit sheet.** Medium detent. Amount (numeric) and unit at the top,
preview of scaled kcal/macros, "More details" disclosure with name and
nutrients, Delete food (destructive, confirmation), Ask Pip to fix this. It
saves through the existing `editItem` path with its revision check.

## AI-first parity (owner requirement)

Every edit reachable in the redesigned Diary must also be doable by asking
Coach, through the same store operation and revision checks. Existing tools
already cover: food edit (`edit_item`, `correct_item`), `move_meal`,
`delete_meal`, coverage (`close_day`), weight (`log_weight`, `delete_weight`)
and workouts (`log_workout`, `edit_workout`, `delete_workout`). This delivery
adds `delete_item`. The plan must audit the remaining manual controls (mark
estimate reviewed, add note or photo, "I ate half", photo delete) and either
point to the existing Coach path or add the tool in this delivery; a manual
control without a Coach path does not ship.

## Builder calls (settled, not owner decisions)

- Week strip spans the first recorded day through today; each visible week
  loads through a small bounded store query by local-date range (recorded days
  only; empty days render as empty pills, never stored).
- On a date with no recorded day the coverage chip is hidden.
- The `+` menu acts on the selected day and is disabled when it has no record.
- Changing only the amount scales recorded nutrients proportionally, the
  existing `FoodItemEditor` rule; the preview uses the same rule and unknown
  values stay unknown.
- `openDiaryCoach` is already available in the Diary tab (the day screen uses it).

## Delete food

Add a store operation that removes one `FoodItem` from a meal, using the same
expected-revision and profile-ownership checks as `editItem`, bumping revision,
recomputing totals, and keeping backup/archive behavior. Deleting the last food
is not allowed from the sheet; the sheet offers Delete meal instead. Add the matching Coach tool
so a person can say "remove the toast", with receipts and replay protection
like `applyCoachItemCorrection`. On a one-food meal the tool does not delete;
Pip asks whether to delete the meal, and only the existing delete-meal path
acts after confirmation. Tests first: store unit test (revision
conflict, last-item guard, totals) and a Coach tool test.

## Constraints kept

Precision Glass tokens and semantic colors; Liquid Glass only on navigation and
controls; Dynamic Type including accessibility sizes (strip pills and rows
stack); VoiceOver labels for pills ("Tuesday 14 October, partial, 3 meals"),
44-pt targets; Reduce Motion disables strip paging animation; English only.
Unknown nutrition stays "—", never zero. Missing days are never invented.
Existing accessibility identifiers used by UI tests are kept or the tests
updated in the same change. Profile change resets the selected day.

## Non-goals

Today tab layout, the Log meal composer, manual nutrition entry, Progress,
Coach timeline, new Pip poses on Diary (no mascot on detail screens), search,
creating a recorded day for an empty past date from the composer.

## Left to the builder

Paging implementation for the strip (`ScrollView` with `.scrollTargetBehavior(.paging)`
preferred), how history pages feed the strip, exact macro bar styling within
the existing palette, and file split (new `DiaryWeekStrip`, reuse `NutritionSummary`
and `MealRow`).
