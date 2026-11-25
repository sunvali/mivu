# Pip notices

Design, 2026-11-25. Based on `main` at `7247c348` (iOS 1.9.1). iOS first;
Android follows later and is not part of this work.

## Why

There are thousands of calorie apps and "photo to calories" is a commodity.
The owner chose to make Mivu special by making Pip feel like someone who
knows you, because that grows with every week of use and a scanner app
cannot copy it.

Today Pip only knows you when asked. Coach reads recent meals when a message
is sent, but Pip never raises anything himself, and his own lines are the
same for everyone ("Morning! What's for breakfast?", "Dinner time?").

This work makes Pip say one true, personal thing a day that only something
holding your history could say.

## What the person experiences

Once a day at most, Pip says a short observation about the person's own
diary, in two places that already exist:

- **Pip's bubble in Coach**, in place of the time-of-day greeting.
- **The morning check-in card on Today**, as one line under yesterday's recap.

When the observation invites action, an offer sits beside it. Tapping the
offer sends a ready message to Coach, which answers as it does today.

Examples (English; final copy is the builder's, inside the tone rules):

| Kind | Pip says | Offer |
| --- | --- | --- |
| Weekend drift | "Weekends tend to run over for you." | "Plan a lighter weekend" |
| Weekday drift | "Thursdays usually run over for you." | "Plan today with me" |
| Day runs under | "Mondays usually come in well under." | "Easy ideas to fill the day" |
| Win | "6 of 7 days near target. Your best week this month!" | none |
| Win | "5 days near target this week, up from 3." | none |
| Welcome back | "Good to see you again. Pick up from today?" | none |
| Late dinners | "Dinner landed after 9:30 three times this week." | "Earlier dinner ideas" |
| Late first meal | "Your first meal came after 1 pm most days this week." | "A quick earlier option" |
| Protein | "Protein came in short on 9 of your last 12 logged days." | "Easy ways to add protein" |

New users see exactly what they see today until there is enough history.

## Decided by the owner

- Build "Pip notices" first, before "Pip remembers what you tell him" and
  "Pip knows your usuals".
- Notice all four families: days that drift, wins, meal timing, nutrient gaps.
- Show it in Pip's bubble and the morning card. No notifications, no new screen.
- When a pattern is unflattering, Pip says it kindly, without blame, with one offer.

## Goals

- Every sentence is true and matches the Progress screen for the same days.
- Works offline and without a ChatGPT connection (the offer needs one).
- Costs the person none of their ChatGPT usage until they tap an offer.
- Never feels like nagging.

## Non-goals

- Push notifications or a weekly letter.
- Remembering facts the person tells Pip; learning usual meals.
- Sentences written by the model.
- Weight-trend observations (Progress already has its headline).
- New screens, new Pip artwork, Android.

## Anti-goals: these make it a failure even if it works

- A claim made on thin data, or a number that disagrees with Progress.
- Guilt: "bad", "cheating", "failed", streak counts, broken-streak language.
- Suggesting skipped meals or eating below target.
- The same observation day after day.
- Pip saying something that Coach then does not know about.

## How it works

### Detection

A pure function, on the device, in the app's analysis layer next to
`ProgressAnalytics`. It takes plain values and returns candidate notices,
so it has no database or UI dependency and a later server worker could use it.

Input:

- The last 30 daily reports ending yesterday, from the existing bounded
  query `progressRange(endingOn:days:includeDailyReports:)` with `days: 30`
  (it accepts 1, 7, 30, 91 and 365 only). Only closed days count; skipped
  and missing days are left out, as Progress does.
- First and last meal time for each of the last 7 closed days, from the
  existing bounded query `recentMeals(from:to:)` that the quick prompts
  already use. A meal's time counts only when its
  `timePrecision` is `.exact`, or when the precision is nil (older data)
  and the capture time is within two hours of the eaten time. `.dateOnly`
  meals carry no real time and are ignored, as `QuickPrompts` already does.
- The calendar (for weekends) and today's weekday.

"Near" and "off" reuse `ProgressBand`. Near is the `.near` band. Off means
more than 20% from that day's own target, which is the `.off` and `.farOff`
bands together. Direction (over or under) is kept, because wording differs.

Detection runs once per waking day per profile, off the main thread, the
first time Today or Coach appears that day. The chosen notice is stored
with its date, so the scan is not repeated.

Rules for the first version:

| Kind | Fires when | Shown on |
| --- | --- | --- |
| Welcome back | The last closed day with food is 3 or more days ago | That day |
| Best week | Near-target days in the last 7 closed days is at least 4 and beats each of the three weeks before | Any day |
| Better week | At least 4 near-target days in the last 7, and at least 2 more than the 7 before | Any day |
| Weekend drift | Weekend days are off in the same direction on at least 3 of the last 4 weekends, and weekdays are mostly near | The day before the weekend, and weekend days |
| Weekday drift | One weekday is off in the same direction on at least 3 of its last 4 occurrences | That weekday |
| Late dinners | Last meal at 21:30 or later on at least 3 of the last 7 closed days | Any day |
| Late first meal | First meal at 13:00 or later on at least 4 of the last 7 closed days | Any day |
| Protein short | A protein target is set, and protein was under 80% of it on at least 60% of the closed days with known protein in the last 14, with at least 5 such days | Any day |

Weekends come from `Calendar.current`, so Friday and Saturday in Israel and
Saturday and Sunday in the USA.

Nothing fires until the profile has 14 logged days (`loggedDayCount`, which
is all-time). Each rule's own minimum then guards against a thin recent window.

### Choosing one

At most one notice per waking day, per profile.

- Order of preference: welcome back, then a win, then a drift that applies
  today, then timing, then protein.
- A kind that was shown rests for 7 days.
- At most two notices that are not wins in any 7 days.
- If nothing qualifies, Pip says his usual greeting.

The record of what was shown (kind, its counts, the date, and whether the
offer was tapped) is small and per profile. Keep it in `UserDefaults` keyed
by profile ID. Losing it on a new phone is harmless, so it does not belong
in the diary or the backup.

### Showing it

- **Coach bubble.** `PipLine.current` gains the notice as an input. It
  replaces the greetings Pip says before the first meal of the day, both
  the full lines and the short ones beside the chips. Recovery, working,
  connect, typing and the swipe tip keep their current priority, and the
  "Anything else?" lines after a meal stay as they are.
- **Offer chip.** The offer is a `.send` prompt with a stable id, placed
  first in the existing quick-prompt row. It counts toward the row's chip
  limit and cannot be hidden by the person; it goes away with the notice.
- **Morning card.** The full card on Today shows the notice under the
  recap, passed in by `TodayView`, with the offer as a button that opens
  Coach and sends the prompt. The compact card inside Coach does not repeat
  it, since the bubble is there. When the morning card is not showing, the
  notice appears in Coach only.
- **Lifetime.** The day's notice stays until the person taps the offer,
  the first meal of the day is saved from any source, or the day rolls
  over. This is the rule the morning card already follows, so the only new
  stored mark is "offer tapped".
- **Large text.** The bubble already hides greetings at accessibility type
  sizes. The notice follows that rule, so at those sizes it appears only in
  the morning card.
- **Off switch.** One toggle, "Pip's observations", in Settings under
  "Your day", next to "Morning check-in", stored the same way: `@AppStorage`,
  one setting for all profiles. On by default.

### Coach knows what Pip said

- The offer's message states the pattern in the person's voice, for example
  "My Saturdays usually run over target. Help me plan a lighter one." Coach
  then checks the real numbers with `get_progress`, under its existing rule
  that diary numbers must come from context or a tool result.
- Today's notice is also given to Coach in the developer message built at
  request time, read from the shown-notice record, so a hand-typed reply
  such as "what do you mean, Thursdays?" makes sense. It is not added to
  the persisted capture context or manifest, which stay immutable. A turn
  retried on a later day simply no longer carries it.

### Wording

- Fixed, localized sentences in `Localizable.xcstrings` for English,
  Spanish, Russian and Hebrew, like every other Pip line. Whole sentences
  per case, never a word slotted into a sentence.
- Numbers in a sentence are the detector's own counts.
- One short sentence that fits the bubble; the offer is three or four words.
- Gender-neutral in languages with grammatical gender, as Coach already is.
- Tone: an observation, then at most one offer. Over target gets a lighter
  option. Under target gets ideas to reach the target. Timing is stated as
  a fact, never as a fault.

## Constraints

- Follow `AGENTS.md`: failing test first, platform APIs first, minimal Swift.
- Coach paths stay on bounded owner queries; do not rebuild a full
  `DiarySnapshot`.
- VoiceOver reads the notice and the offer; touch targets stay at 44 points;
  Dynamic Type and Reduce Motion are respected.
- No new dependency, no new network call, no new stored diary record type.

## Checks

- Unit tests on the detector with synthetic days: each rule fires at its
  threshold and stays silent just below it, thin data stays silent, Israel
  and USA weekends, over versus under.
- Unit tests on choosing: one per day, 7-day rest, the two-per-week cap.
- `PipLine` tests: the notice replaces only the greeting.
- One UI test with a launch fixture: the notice in the Coach bubble, the
  offer chip sending its message, and the line in the morning card.
- Before the PR: UX/UI review of real screenshots and a QA pass on a
  simulator, then Ponytail Review.

## Left to the builder

- Type and file names.
- Final copy in the four languages, inside the tone rules.
- Whether Pip plays an existing gesture when a win shows. No new artwork.
- Exact layout of the notice line in the morning card.

## Calls made by the author, not by the owner

- Sentences are fixed templates, not written by the model.
- Thresholds in the rules table, including 14 logged days before anything shows.
- "Nutrient gaps" means protein short of the person's own target only.
  Mivu tracks calories, carbs, protein and fat, and protein is the one
  where a shortfall is a useful thing to hear.
- "Meal timing" means late dinners and a late first meal. Long gaps
  between meals are left out of the first version.
- A welcome back after 3 or more days away is included as a win.
- The off switch, and that it is stored like the morning check-in toggle,
  so it is one setting for all profiles.
- The shown-notice record lives in `UserDefaults`, outside the backup.
- The notice goes away once the first meal of the day is saved, like the
  morning card. A notice about dinner is therefore seen in the morning or
  at first open, not in the evening.
- Coach learns of the notice through the request-time developer message,
  not through the persisted capture context.
- The offer chip cannot be hidden and counts toward the chip limit.
