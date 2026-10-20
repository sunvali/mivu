# Day rollover and morning check-in — design

## Why

Today a new waking day starts only from a hidden "Start new day" menu or a weigh-in.
After midnight, every log asks "Which waking day?". Users forget the menu, and the
popup interrupts them while they log. The day should change by itself, at a
predictable moment. Weight stays optional, and nothing ever blocks logging.

## What others do (research)

- Most food diaries use plain midnight on the phone's clock. Nutrola documents
  this, so a 00:10 snack counts for the next day. Users work around it by
  backdating ([Nutrola help](https://nutrola.app/en/help/which-day-a-late-night-meal-counts-toward),
  [r/MacroFactor thread](https://cal1.lr.ggtyler.dev/r/MacroFactor/comments/1cy3xd5/late_night_snacks_and_logging)).
- Weigh-ins work best first thing in the morning, at about the same time each day.
  Daily swings of 1–5 lb are noise. Only the trend matters, and missing days are
  fine ([Carbon](https://help.joincarbon.com/en/articles/6044265-weighing-in-consistently),
  [MacroFactor trend weight](https://help.macrofactorapp.com/dashboard/weight_trend/)).
- Reminders are opt-in, with a time the user picks.

Mivu keeps its waking-day model, which handles late snacks better than midnight.
This design adds a predictable automatic trigger.

## Rules

1. **Cutoff.** The default is 4:00 AM local time. It can be changed in Settings
   (the "Day starts at" hour, 0–8).
2. **Rollover.** The first activity after the cutoff starts the new day, when the
   active day began on an earlier waking date. Activity means the app coming to
   the foreground, or any log (meal, weight, Coach, Shortcut).
   - Uses the existing `startDay(at:)`. A repeated trigger reuses the open day, as it does now.
   - The waking date of an instant is the local date of `instant − cutoff`. So 01:30
     belongs to the previous date, and 04:30 to today.
   - Gaps are fine. After three days away, the next open starts today, and no empty
     days are created in between.
3. **Late meals.** The "Which waking day?" popup is removed from the composer and
   from manual nutrition. A meal goes to the active day by the rules above. Then a
   toast says where it went: "Added to Tue, Oct 20 · Change", where Change moves it
   to the other day using the existing meal move. The toast shows only when the
   meal landed on a day whose date differs from the calendar date of the moment
   it was eaten.
   - Coach's `needsDayChoice` clarification goes away in the same way. Coach saves
     to the active day and says which day.
   - The four-hour `previousDayConfirmedAt` window is no longer needed for new
     decisions. The field stays readable for old diaries and backups.
4. **Time zone change.** The existing behavior stays: the profile zone decides.
   The cutoff applies in that zone.

## Morning card

- **When it shows:** at the top of Today, after a rollover, until the first meal
  of the new day is saved or the user dismisses it. The dismiss button is an
  X, and it hides the card for that day only.
- **Pip:** says "Good morning". It uses the `greeting` gesture, then `attentive`.
- **Yesterday:** the kcal total against the target, with a progress bar. Numbers
  only, with no ChatGPT, so it works offline. If yesterday has no target, it
  shows just the total.
  - Then a question: "Did you log everything yesterday?" with **Yes** and
    **Not quite**. The answer sets that day's completeness (`complete` or
    `incomplete`) through the existing `setCompleteness`. If the user doesn't
    answer, the day stays `unknown`.
  - If yesterday has no meals, the recap and question are hidden.
- **Weight:** shown every morning, always optional.
  - A large weight field with a unit menu (kg or lb). It defaults to the last
    unit used and is prefilled with the last weight as a placeholder. There is
    a Save button and a Skip button.
  - On save, Pip nods (`saved`). The card then shows the 7-day trend, for example
    "−0.4 kg this week": the average of the last 7 days minus the average of the
    7 days before. The trend shows only with at least two weigh-ins in each
    window. Otherwise it shows "Saved".
  - The weight is recorded on the new day: `recordWeight(startNewDay: false)`,
    since the day is already open.
- **Done state:** when both the question and the weight are answered or skipped,
  the card collapses to one line. It goes away at the first meal.
- Polish bar: Apple/Airbnb level. The card uses `DiarySummaryCardStyle`, has
  smooth insert and remove transitions (opacity only under Reduce Motion), and
  haptics on save. It has 44-pt targets, VoiceOver labels and Dynamic Type
  (Pip shrinks at accessibility sizes).

## Morning reminder

- In Settings: a "Morning check-in" toggle, off by default, with a time (default
  8:00).
- Turning it on asks for notification permission at that moment, never before.
- It is one repeating local notification: "Good morning — log your weight or
  breakfast." Tapping it opens Today.
- It is local only: no server and no push service.

## Settings

- "Day starts at" (hour picker).
- "Morning check-in" toggle and time.
- "Start new day" stays in the Today day menu as a manual override. The
  confirmation dialog is removed, since an accidental start can be undone by
  moving meals and a repeated start reuses the open day.

## Data

- Cutoff hour, reminder on/off and reminder time are device preferences
  (`@AppStorage`), not diary data.
- No schema change. Completeness, weights and days use existing records.
- The last-used weight unit is a device preference.

## Constraints

- English only. Accessibility as above.
- Synthetic inputs only in tests.
- Native SwiftUI and `UserNotifications`. No new dependencies.
- Never block logging on weight, the question or the reminder.

## Non-goals

- Sleep detection from Apple Health.
- A ChatGPT recap of yesterday.
- Backfilling empty days.
- Streaks.

## Tests (smallest meaningful)

- The waking-date function at 01:30, at 04:00 exactly, at 04:30, and with a
  custom cutoff.
- A rollover on foreground with the active day from an earlier date starts one
  day; a second trigger reuses it.
- A meal at 01:30 lands on the previous waking day with no question.
- The trend: at least two weigh-ins per window shows a value, fewer shows
  nothing.
- One UI test: the morning card appears after a synthetic rollover, Skip works,
  and logging a meal hides the card.

## Left to the builder

- Copy tone and card layout, within the design system.
- Exactly where the toast lives (Today overlay or composer dismissal).
- How the reminder deep-links to Today.
