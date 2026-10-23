# Progress tab redesign: colorful, chart-first insights

Status: draft for owner approval · 2026-10-23
Mockup (synthetic numbers): [assets/2026-10-23-progress-insights-mockup.png](assets/2026-10-23-progress-insights-mockup.png)

## Intent

Today the Progress tab is mostly sentences ("Carbs goal 200 g; recorded 150 g; remaining 50 g"), one
calorie bar chart, and weight behind a link. The owner wants an enterprise-grade tab that answers, at a
glance and with pictures rather than numbers:

1. **Am I on track?**
2. **Is my weight moving?**
3. And makes checking in **fun and rewarding**.

It must look like the rest of Mivu (same palette, white 24pt cards, SF type, Pip, native controls) — no
new design language — but it may be **more colorful** than today.

## Goals

- One plain headline answer at the top, with Pip reacting to the period.
- Diagrams first: week bars, macro donut, smoothed weight trend, logging calendar, calories-vs-target
  bars, estimated burn, top foods.
- One shared color scale for "how far off target" a day was, used everywhere a day is colored.
- Every card opens a detail screen with scrollable history.
- Ranges: **Week · Month · 3M · Year**.

## Non-goals

- No Apple Fitness–style rings (owner: too complicated, people don't remember them).
- No new nutrients beyond kcal, protein, carbs, fat.
- No changes to how meals are logged or how goals are edited (the existing Goals editor stays).
- No Chart3D.

## Anti-goals (a failure even if it works)

- **Shame.** No red "you failed" verdicts, no sad Pip, no streak that resets to zero and scolds.
- **Missing counted as zero.** The existing rule stays: a day with no log is shown as "no log",
  never as 0 kcal, and is excluded from averages.
- **Raw scale noise as the hero.** Daily weigh-ins are faint dots; the smoothed trend is the line.
- **A wall of cards with no hierarchy.** The headline first, then the period story, then insights.

## Research basis

From a web research pass (sources in the session report): MacroFactor's smoothed weight trend
over faint daily dots and its expenditure estimate; MacroFactor's intake-vs-target bars; Oura's use of a
personal baseline and a segmented range control; Duolingo's lesson that unforgiving streaks cause
anxiety (so we show a calendar, not a streak counter); WWDC23 `SectorMark` donut guidance; Audio
Graphs via `AXChartDescriptor`. Opinion-level items were treated as such.

## The screen, top to bottom

Large title **Progress**, then a native segmented control **Week · Month · 3M · Year** (replaces
Day / 7 days / 30 days; "Day" is covered by the Today tab).

### 1. Headline card (summary-surface tint, Pip on the right)

- Date range caption (accent), headline in large bold accent type, one supporting sentence.
- **"On track" is weight-trend-first (owner decision):** when a goal weight exists and the trend has
  enough data, the headline says whether the smoothed trend is moving toward the goal over the period
  ("You're on track", "Holding steady", "Drifting from your goal" — always kind wording).
  *Builder's call, marked:* when there is no goal weight or too few weigh-ins, fall back to calories:
  on track when most logged days are within 10% of the calorie target.
- The supporting sentence states the evidence (e.g. "Trend down 0.4 kg this week · 4 of 6 logged days
  near your 2,100 kcal target").
- Below: **period bars** — one bar per day (Week) or per day/week bucket for longer ranges, colored by
  the off-target scale, a dashed neutral target line, today labelled, missing days drawn as a dashed
  outline. A key under the chart: Near · A bit off · Off · Far off · No log.
- **Pip mood follows the period and is always encouraging (owner decision):** cheering on a good
  period, gentle/encouraging pose with a line like "New week, fresh start" on an off period. Never sad.
  Uses existing `PipRigView` poses/gestures (see the mivu-animation skill); reduced motion respected.

### 2. Small wins (horizontal chips)

Tinted chips with a colored glyph and two lines, e.g. "Protein goal 4 days running · New personal
best", "6 days logged · Best week this month", "Weighed in 5 mornings". Computed from the period only;
never a "you broke your streak" chip. Hidden when there is no win. *Builder's call:* a small fixed list
of win rules, at most three chips, most notable first.

### 3. Average day (macro donut)

`SectorMark` donut of average protein / carbs / fat calories with the average kcal in the center,
plus a legend: each macro's average grams vs its goal with a thin progress bar, in the existing macro
colors. Averages use only logged days (the existing known-sample rule).

### 4. Weight trend (blue tint)

Big current **trend** value in protein-blue, a delta pill ("↓ 1.2 kg this month"), a chart of faint
daily points plus a bold smoothed line with a soft area, a dashed goal line, a start → goal progress
bar and "3.4 kg to go". Copy explains the dots vs the line once. *Builder's call:* exponential moving
average (MacroFactor-style); smoothing constant chosen and unit-tested.

### 5. Logging calendar

Month grid (Mon-first, matching the mockup) where each logged day's cell uses the same off-target
color scale, missing days are dashed outlines, future days are blank, today is outlined. Caption:
"19 of 23 days logged so far, 15 near target." For 3M/Year, *builder's call:* a compact
contribution-style grid (weeks as columns).

### 6. Insights

- **Calories vs target:** bars for the range, same color scale, dashed target line, average in the
  caption.
- **Estimated burn (green tint):** daily energy expenditure estimated from intake and the weight
  trend, with an uncertainty band that narrows as data grows; caption "From your intake and weight
  trend. Firms up after 2 weeks of logs." *Builder's call:* energy-balance method (average intake −
  trend change × ~7,700 kcal/kg ÷ days), only over complete logged days, shown only after the
  minimum data threshold.
- **Top foods by calories (warm tint):** the period's highest-calorie foods with a colored share bar
  and kcal; "All foods ›" opens the full list.
- **Links:** Workouts (count this period ›) and Goals (Manage ›) keep their existing destinations.

### Not enough data (owner decision)

A card never disappears for lack of data. It keeps its frame and shows a friendly placeholder with Pip
and what unlocks it, e.g. "Log 9 more days to see your burn", "Add a goal weight to see how far is
left", "Weigh in on 2 more days to see your trend".

## The off-target color scale (owner decision)

Distance from the target as a share of the target, the same everywhere a day is colored:

| Band | Distance | Color | At 2,100 kcal |
|---|---|---|---|
| Near | ≤ 10% | accent teal `diaryAccent` | ≤ 210 kcal |
| A bit off | ≤ 20% | light amber | ≤ 420 kcal |
| Off | ≤ 35% | orange | ≤ 735 kcal |
| Far off | > 35% | coral | > 735 kcal |
| No log | — | dashed outline | — |

Over and under use the same band (distance only). The three new colors are added to
`ios/Shared/MivuColors.swift` as adaptive light/dark/high-contrast tokens like the existing ones, and
coral must not read as the error red. Color is never the only signal: VoiceOver values and the chart
summaries name the band.

## Detail screens (owner: every card opens one)

Each card is a `NavigationLink` to a full screen with the same chart at full width, horizontal
scrolling through history (`chartScrollableAxes`, snapping by day/week/month), tap-to-select values,
and a plain list underneath. Weight and Workouts keep their existing ledgers, editing, Ask Pip and
paging; their screens are restyled to match. New detail screens: Calories, Macros, Calendar, Estimated
burn, All foods.

## Color and style rules

- Existing tokens first: `diaryAccent`, `diaryProtein`, `diaryCarbs`, `diaryFat`, `diarySuccess`,
  `diarySummarySurface`, `diaryChartSurface`, plus the three band colors above and two light card tints
  (green for burn, warm for foods), all adaptive with dark and high-contrast values.
- Cards keep `diarySummaryCard()` geometry (24pt radius, current shadow and hairline). Tinted cards
  swap only the fill.
- No gradients beyond the soft area under the weight line and the burn band.

## Constraints

- **AGENTS.md:** Dynamic Type (charts reflow; legends stack at accessibility sizes), VoiceOver, reduced
  motion, 44pt targets, English only, Ponytail minimal code, platform APIs first (Swift Charts,
  `SectorMark`, `RectangleMark`, `chartXSelection`, `chartScrollableAxes`).
- **Accessibility:** every chart has a text summary (the existing `nutritionChartSummary` /
  `weightChartSummary` pattern) and, *builder's call*, an `AXChartDescriptor` for Audio Graphs on the
  main charts.
- **Data honesty:** missing ≠ zero; pending analysis days marked; incomplete days lighter or noted;
  numbers in the copy always match the charts.
- **Bounded queries:** `progressRange` accepts only 1/7/30 days with a 37-day horizon today. 3M and
  Year need new bounded aggregate queries (weekly buckets for 3M, monthly for Year); do not rebuild a
  full `DiarySnapshot` (per AGENTS.md Coach rules). Top foods needs a new grouped query over saved meal
  items in the range.
- **Profile switching:** keep the existing ownership/generation guards on every load.
- **Tests:** unit tests for the off-target band function, trend smoothing, expenditure estimate,
  on-track decision (both branches), win rules and the new queries; smoke run plus the existing
  Progress UI tests updated (identifiers `progressList`, `openWeight`, `openWorkouts`, `editGoals`,
  `missingDayCopy` etc. keep working or are migrated deliberately).

## Resolved details (from the builder check)

Answered from the project:

- **Goal weight already exists:** `GoalRecord.goalWeightKg`, edited in the Goals editor ("Optional
  weight goal") and by the Coach. No model change is needed.

Settled as my calls (marked so the owner can check them):

- **Start weight** = the trend value at the first weigh-in on or after the active goal's
  `effectiveLocalDate`; "to go" = current trend − goal weight.
- **Goal direction** = sign of (goal weight − start weight). Within ±1 kg of the goal counts as
  maintaining, and the headline reads "At your goal" when the trend stays within ±1 kg.
- **On-track thresholds (weight branch):** "You're on track" when the trend moved toward the goal by
  ≥ 0.1 kg per week over the period. "Holding steady" when it moved less than that either way.
  "Drifting from your goal" when it moved away by ≥ 0.1 kg per week. Wording stays kind; Pip stays
  encouraging.
- **Minimum data:** a weight trend needs ≥ 3 weigh-ins spanning ≥ 7 days. The weight branch of the
  headline needs that plus a goal weight. Estimated burn needs ≥ 14 complete logged days and ≥ 4
  weigh-ins spanning ≥ 14 days. Placeholders count down to exactly these numbers. The burn band
  width shrinks with the number of qualifying days (wide at 14, narrow by about 30), and the
  formula is unit-tested.
- **Ranges:** Week = rolling 7 days ending today (matches today's behaviour and the mockup), Month =
  rolling 30, 3M = 13 weekly buckets, Year = 12 monthly buckets. The calendar follows the range:
  Week and Month show the current calendar month grid, while 3M and Year show a weeks-as-columns
  contribution grid.
- **Target changes inside a range:** each day is banded against that day's own goal
  (`goal(on:)`). The chart's target line is stepped (`RuleMark` segments per goal span). Copy quotes
  the current goal.
- **Data source:** the display path of `progressRange` (`progressForDisplay`) accepts 91 and 365 days
  as well as 1/7/30, reusing its existing per-day logic, with a performance test (365 seeded days
  under 1 s on the simulator). It is rewritten as grouped SQL only if that test fails. All cards
  (headline, bars, calendar, burn, wins) derive from this one result, and the Coach's own day limits
  are unchanged.
- **Top foods:** grouped by case- and whitespace-normalized item name, summing kcal over saved meals
  in the range. Items with unknown kcal and pending meals are excluded, and the footnote says so.
- **Detail history:** paged by range windows (scroll back loads the previous window) until the first
  record. There is no unbounded single query.
- **UI tests:** existing Progress UI tests are migrated deliberately. Keep `progressList`,
  `openWeight`, `openWorkouts`, `editGoals` and `missingDayCopy`. Replace `reportDaily`,
  `reportWeekly` and `reportMonthly` with the segmented control's identifiers, and update the
  assertions in the same change.

## Left to the builder

Exact pose mapping for Pip moods; win rule list; smoothing and expenditure constants; 3M/Year bucket
rendering; dark-mode tint values; animation timings (respect reduced motion); how the detail screens
share chart code; whether the existing `GoalSummaryView` survives anywhere.
