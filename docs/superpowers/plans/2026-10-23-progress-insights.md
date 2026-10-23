# Progress Insights Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the text-heavy Progress tab with a colorful, chart-first tab (headline + Pip, wins, macro donut, weight trend, logging calendar, calories vs target, estimated burn, top foods), each card opening a detail screen.

**Architecture:** Pure insight math lives in one new file (`ProgressInsights.swift`) with unit tests. Data comes from the existing `progressForDisplay` path widened to 91/365 days plus one new grouped `topFoods` query. SwiftUI cards live in a new `ProgressCards.swift`; `ProgressView.swift` keeps its loading/ownership guards and composes the cards; new detail screens live in `ProgressDetailViews.swift`.

**Tech Stack:** Swift 6, SwiftUI, Swift Charts (`BarMark`, `LineMark`, `AreaMark`, `PointMark`, `RuleMark`, `RectangleMark`, `SectorMark`, `chartXSelection`, `chartScrollableAxes`), SQLite via `DiaryDatabase`, Swift Testing, XCUITest, XcodeBuildMCP.

**Spec:** [docs/superpowers/specs/2026-10-23-progress-insights-design.md](../specs/2026-10-23-progress-insights-design.md) (mockup: `docs/superpowers/specs/assets/2026-10-23-progress-insights-mockup.png`)

## Global Constraints

- Same design language: existing color tokens, `diarySummaryCard()` geometry (24pt radius), SF type, native controls; "may be more colorful".
- Off-target bands, distance only, against that day's own goal: Near ≤ 10%, A bit off ≤ 20%, Off ≤ 35%, Far off > 35%; no log = dashed outline, never zero.
- Ranges: Week = rolling 7 days ending today, Month = rolling 30, 3M = 91 days shown as 13 weekly buckets, Year = 365 days shown as 12 monthly buckets.
- Minimum data: weight trend ≥ 3 weigh-ins spanning ≥ 7 days; burn ≥ 14 complete logged days and ≥ 4 weigh-ins spanning ≥ 14 days.
- On-track (weight branch): toward goal ≥ 0.1 kg/week → on track; |move| < 0.1 kg/week → holding steady; away ≥ 0.1 kg/week → drifting; trend within ±1 kg of goal → at goal. Fallback (no goal weight or too few weigh-ins): on track when more than half of logged days are Near.
- Kind copy only; Pip never sad. Cards never disappear for lack of data — they show a placeholder naming what unlocks them.
- AGENTS.md: Dynamic Type, VoiceOver (text summary per chart), reduced motion, 44pt targets, English only, missing ≠ zero, ownership/generation guards on every load, synthetic test data, Conventional Commit titles, no "ai"/assistant mentions in commits/PRs.
- Tests proportional: run only the named suites per task; smoke via `python3 scripts/ci/smoke.py --simulator-id <reserved-UUID>` in Task 7.

## Review Focus

1. **A goal that changes mid-range** — each day banded against its own goal; target line stepped. Test in Task 1 (`bandUsesEachDaysOwnGoal`).
2. **Pounds entries** — weights stored in lb must be converted to kg before smoothing/headline. Test in Task 2 (`trendConvertsPounds`).
3. **Pending or unknown-kcal days** — excluded from bands, averages, burn and top foods, never zero. Tests in Task 1 (`unknownKcalHasNoBand`) and Task 4 (`topFoodsSkipsUnknownAndPending`).
4. **Profile switch while a 365-day load is in flight** — stale result must not render. Covered by keeping the existing `reportRequest` guard; asserted in Task 5 (`switchingProfileDropsStaleRange` unit test on the load helper).
5. **Gaps of weeks between weigh-ins** — smoothing must weight by elapsed days, not by sample count. Test in Task 2 (`trendWeightsByElapsedDays`).

---

### Task 1: Band colors and the off-target scale

**Files:**
- Create: `ios/Mivu/Progress/ProgressInsights.swift`
- Modify: `ios/Shared/MivuColors.swift`
- Test: `ios/MivuTests/ProgressInsightsTests.swift`

**Interfaces:**
- Produces: `enum ProgressBand: Int, CaseIterable { case near, bitOff, off, farOff }` with `static func of(kcal: Double?, target: Double?) -> ProgressBand?`, `var title: String` ("Near", "A bit off", "Off", "Far off"), `var color: Color`.
- Produces colors: `Color.diaryBandBitOff`, `.diaryBandOff`, `.diaryBandFarOff`, `.diaryTintBurn`, `.diaryTintFoods` (Near uses `diaryAccent`).

- [ ] **Step 1: Write the failing tests** in `ProgressInsightsTests` (`@Suite struct ProgressInsightsTests`):

```swift
@Test func bandsByDistanceFromTarget() {
    #expect(ProgressBand.of(kcal: 2310, target: 2100) == .near)     // exactly 10%
    #expect(ProgressBand.of(kcal: 1680, target: 2100) == .bitOff)   // 20% under
    #expect(ProgressBand.of(kcal: 2835, target: 2100) == .off)      // 35% over
    #expect(ProgressBand.of(kcal: 2836, target: 2100) == .farOff)
}
@Test func unknownKcalHasNoBand() {
    #expect(ProgressBand.of(kcal: nil, target: 2100) == nil)
    #expect(ProgressBand.of(kcal: 1800, target: nil) == nil)
    #expect(ProgressBand.of(kcal: 1800, target: 0) == nil)
}
@Test func bandUsesEachDaysOwnGoal() {
    // same intake, different goals on different days
    #expect(ProgressBand.of(kcal: 2000, target: 2000) == .near)
    #expect(ProgressBand.of(kcal: 2000, target: 1500) == .off)
}
```

- [ ] **Step 2: Run to verify failure** — XcodeBuildMCP test, `-only-testing:MivuTests/ProgressInsightsTests`. Expected: build fails, `ProgressBand` undefined.
- [ ] **Step 3: Implement** `ProgressBand` (distance = |kcal − target| / target; inclusive upper bounds 0.10 / 0.20 / 0.35). Add the five colors with `adaptive(light, dark, highContrastLight:, highContrastDark:)`: bitOff `0xF4BC62`/`0xF4BC62`, off `0xE8893A`/`0xF0A060`, farOff `0xD9604C`/`0xF08A78` (keep it visibly distinct from `diaryError` `0xB33143`), tintBurn `0xE8F4EC`/`0x15291E`, tintFoods `0xFBF3E6`/`0x2A2216`; choose high-contrast variants with ≥ 3:1 against `diarySurface`.
- [ ] **Step 4: Run to verify pass.** Same command. Expected: 3 passed.
- [ ] **Step 5: Commit** `feat(progress): off-target bands and colors`.

### Task 2: Weight trend and the on-track headline

**Files:**
- Modify: `ios/Mivu/Progress/ProgressInsights.swift`
- Test: `ios/MivuTests/ProgressInsightsTests.swift`

**Interfaces:**
- Consumes: `CoachWeightReference` (`localDate`, `record.value`, `record.unit`), `GoalRecord.goalWeightKg`, `DailyProgress`, `ProgressBand`.
- Produces:
  - `struct TrendPoint: Equatable { let localDate: String; let raw: Double; let trend: Double }` (kg)
  - `enum WeightTrend { static func points(_ weights: [CoachWeightReference], zone: String) -> [TrendPoint] }` — sorted by date, one weigh-in per date (already deduped upstream), lb × 0.45359237.
  - `enum ProgressHeadline: Equatable { case onTrack, holdingSteady, drifting, atGoal, caloriesOnTrack(near: Int, logged: Int), caloriesOff(near: Int, logged: Int), notEnoughData }` with `var title: String` and `var celebrates: Bool` (true for `.onTrack`, `.atGoal`, `.caloriesOnTrack`).
  - `static func headline(trend: [TrendPoint], goalWeightKg: Double?, startKg: Double?, days: [DailyProgress], rangeDays: Int) -> ProgressHeadline`

- [ ] **Step 1: Write the failing tests:**

```swift
@Test func trendWeightsByElapsedDays()   // 80 on day 0, 78 on day 21 → trend after = 80 + (78-80)*(1-0.9^21) ≈ 78.22 (±0.01)
@Test func trendConvertsPounds()          // 176.37 lb → raw ≈ 80.0 kg
@Test func headlineOnTrackWhenTrendMovesTowardGoal()   // start 80, goal 75, trend 79.6 → 79.0 over 7 days → .onTrack
@Test func headlineHoldingWhenMoveUnderTenthKgPerWeek()  // 79.60 → 79.55 over 7 days → .holdingSteady
@Test func headlineDriftingWhenMovingAway()             // 79.0 → 79.3 over 7 days, goal 75 → .drifting
@Test func headlineAtGoalWithinOneKg()                   // trend 75.8, goal 75 → .atGoal
@Test func headlineFallsBackToCaloriesWithoutGoalWeight() // goalWeightKg nil, 4 of 6 logged Near → .caloriesOnTrack(near: 4, logged: 6)
@Test func headlineFallsBackWhenTooFewWeighIns()        // 2 weigh-ins → calorie branch
@Test func headlineNotEnoughDataWithNothingLogged()     // no weigh-ins, no logged days → .notEnoughData
```

- [ ] **Step 2: Run to verify failure.** Expected: missing symbols.
- [ ] **Step 3: Implement.** Trend = exponential moving average seeded with the first raw value, per-sample α = 1 − 0.9^(elapsed days since previous weigh-in). The weight branch applies when `goalWeightKg != nil`, `trend.count >= 3`, and span ≥ 7 days; rate = (last trend in range − first trend in range) ÷ span days × 7; direction from sign(goal − start). Calorie fallback: logged = days with a band; on track when near × 2 > logged.
- [ ] **Step 4: Run to verify pass.** Expected: 12 passed (with Task 1).
- [ ] **Step 5: Commit** `feat(progress): smoothed weight trend and on-track headline`.

### Task 3: Estimated burn and small wins

**Files:**
- Modify: `ios/Mivu/Progress/ProgressInsights.swift`
- Test: `ios/MivuTests/ProgressInsightsTests.swift`

**Interfaces:**
- Produces:
  - `struct BurnEstimate: Equatable { let kcalPerDay: Double; let band: Double }`
  - `enum BurnProgress: Equatable { case estimate(BurnEstimate), needs(days: Int, weighIns: Int) }`
  - `static func burn(days: [DailyProgress], trend: [TrendPoint]) -> BurnProgress`
  - `struct ProgressWin: Equatable, Identifiable { let id: String; let title: String; let detail: String; let symbol: String; let color: Color }`
  - `static func wins(days: [DailyProgress], weighIns: Int) -> [ProgressWin]` (≤ 3)

- [ ] **Step 1: Write the failing tests:**

```swift
@Test func burnNeedsFourteenCompleteDaysAndFourWeighIns()  // 10 complete days, 3 weigh-ins → .needs(days: 4, weighIns: 1)
@Test func burnFromIntakeAndTrend()   // 28 complete days at 2,100 kcal, trend 80.0 → 79.0 over 28 days → kcalPerDay ≈ 2100 + 7700/28 ≈ 2375 (±1)
@Test func burnBandNarrowsWithMoreDays()  // band(14 days) > band(30 days); band(30) == 100
@Test func winsPreferProteinRunThenLoggingThenWeighIns()  // 4-day protein-target run, 6 logged days, 5 weigh-ins → ids ["protein-run", "logged-days", "weigh-ins"]
@Test func noWinsWhenNothingQualifies()  // 1 logged day, no protein run, 0 weigh-ins → []
```

- [ ] **Step 2: Run to verify failure.**
- [ ] **Step 3: Implement.** Burn uses only complete, non-pending days with known kcal: mean intake − (trend change kg × 7700 ÷ span days). Band = 100 + 300 × max(0, 30 − n) ÷ 16, so 14 days → 400 and ≥ 30 days → 100. Win rules, in order:
  - Longest current run of days with protein ≥ the day's protein target, when ≥ 3 days: "Protein goal N days running".
  - Logged days in range ≥ 5: "N days logged", with detail "Every one counts".
  - Weigh-ins ≥ 3: "Weighed in N mornings".
- [ ] **Step 4: Run to verify pass.**
- [ ] **Step 5: Commit** `feat(progress): estimated burn and small wins`.

### Task 4: Range data — 91/365-day display and top foods

**Files:**
- Modify: `ios/Mivu/Diary/DiaryDatabaseProgressQueries.swift:5-11, 81`
- Modify: `ios/Mivu/Diary/DiaryStore.swift:798`
- Test: `ios/MivuTests/DiaryProjectionIntegrationTests.swift` (add `@Suite` methods)

**Interfaces:**
- Consumes: existing `progressRange`, `transaction.records`, `domainStatement`.
- Produces:
  - `progressForDisplay(endingOn:days:expectedProfileID:)` now accepts `days ∈ {1, 7, 30, 91, 365}`. `displayWeights` covers the whole range (not the last 30) and `dailyReports` covers every day in it.
  - `struct TopFood: Equatable, Sendable { let name: String; let kcal: Double; let count: Int }`
  - `DiaryStore.topFoods(from: String, through: String, limit: Int, expectedProfileID: UUID) throws -> [TopFood]`

- [ ] **Step 1: Write the failing tests:**

```swift
@Test func displayRangeAcceptsQuarterAndYear()  // seed meals on days 1, 60, 300 back; days: 365 → dailyReports.count == 365, savedFoodDates contains all three
@Test func coachRangeStillRejectsYear()          // progressRange(... days: 365) with includeDailyReports false → throws CoachError.invalidArguments
@Test func yearRangeLoadsUnderOneSecond()        // 365 seeded days × 3 meals; ContinuousClock measure < .seconds(1)
@Test func topFoodsGroupsByNormalizedName()      // "Greek yogurt", " greek Yogurt " (2 items, 150 + 150 kcal) and "Pizza" 721 → [Pizza 721, Greek yogurt 300 count 2]
@Test func topFoodsSkipsUnknownAndPending()      // nil-kcal item and a revision-0 meal excluded
```

- [ ] **Step 2: Run to verify failure.**
- [ ] **Step 3: Implement.**
  - The day guard becomes `includeDailyReports ? [1, 7, 30, 91, 365] : [1, 7, 30]`, and horizon = `max(37, days)`.
  - `displayWeights` uses `labels` instead of `horizon.suffix(30)`.
  - `topFoods`: one grouped SQL statement joining `item → meal → day` with `revision > 0`, `localDate BETWEEN ? AND ?` and kcal not null, `GROUP BY lower(trim(name))` and `ORDER BY SUM(kcal) DESC LIMIT ?`. The display name is the most recent item's original spelling.
  - Wrap it in `domainRead` with the profile check, like `progressForDisplay`.
  - If `yearRangeLoadsUnderOneSecond` fails, stop and report the timing: the spec allows a grouped-SQL rewrite, but only as a separate decision.
- [ ] **Step 4: Run to verify pass.** Run `-only-testing:MivuTests/DiaryProjectionIntegrationTests` and `-only-testing:MivuTests/CoachStoreTests`; the Coach callers must be unchanged.
- [ ] **Step 5: Commit** `feat(progress): year-long display ranges and top foods`.

### Task 5: The new Progress tab

**Files:**
- Create: `ios/Mivu/Progress/ProgressCards.swift`
- Modify: `ios/Mivu/Progress/ProgressView.swift` (the `DiaryProgressView` body, `Report`, `reportControls`, `reloadProgress`)
- Test: `ios/MivuTests/ProgressInsightsTests.swift` (bucketing), `ios/MivuTests/ProgressEditorStateTests.swift` only if its helpers move

**Interfaces:**
- Consumes: Tasks 1–4.
- Produces:
  - `enum ProgressRange: String, CaseIterable { case week, month, quarter, year }` with `days` (7/30/91/365) and `title` ("Week", "Month", "3M", "Year").
  - `static func buckets(_ days: [DailyProgress], range: ProgressRange, zone: String) -> [ProgressBucket]`, where `ProgressBucket` has `start: Date`, `averageKcal: Double?`, `band: ProgressBand?` and `loggedDays: Int`. Week and Month are per day, 3M is per week (Mon-start) and Year is per month. A bucket's band is the band of its average against the average goal.
  - Card views, each a `View` taking plain values: `ProgressHeadlineCard`, `ProgressWinsRow`, `ProgressMacrosCard`, `ProgressWeightCard`, `ProgressCalendarCard`, `ProgressCaloriesCard`, `ProgressBurnCard`, `ProgressTopFoodsCard`, `ProgressPlaceholder(symbol:text:)`.
  - Accessibility identifiers:
    - Segmented control: `progressRange`.
    - Cards: `progressHeadline`, `progressWins`, `progressMacros`, `openWeight`, `progressCalendar`, `progressCalories`, `progressBurn`, `progressTopFoods`, `openWorkouts`, `editGoals`.
    - Keep these: `progressList`, `missingDayCopy`, `nutritionChartSummary`, `weightChartSummary`.

- [ ] **Step 1: Write the failing tests:**

```swift
@Test func quarterBucketsByMondayWeek()   // 91 days ending Thu 2026-10-22 → 14 buckets, first starts Mon 2026-07-20
@Test func yearBucketsByMonth()           // 365 days ending 2026-10-22 → 13 buckets (partial first/last month)
@Test func bucketsSkipMissingDaysNotZero() // a bucket with only missing days → averageKcal nil, band nil
@Test func switchingProfileDropsStaleRange() // DiaryProgressView.loadProgress throws wrongOwner when selection changes mid-load (existing helper, add the 365-day case)
```

- [ ] **Step 2: Run to verify failure.**
- [ ] **Step 3: Implement the screen** in mockup order:
  1. `Picker` (`.segmented`) bound to `ProgressRange`, replacing the Day / 7 / 30 buttons.
  2. Headline card (`diarySummarySurface`). Use `CompanionView(presentation: CompanionOutput(pose: headline.celebrates ? .dayComplete : .welcomeBack, playback: reduceMotion ? .staticPose : .animated, reactionID: nil, nextDeadline: nil), …)` with its own `CompanionRuntime`, loaded the way `OnboardingView` does at lines 85–89. The card shows the title, the evidence sentence and the bucket bars with a stepped `RuleMark` target and a band key.
  3. Wins row (hidden when empty).
  4. Macros donut: `SectorMark` with `innerRadius: .ratio(0.62)` and `angularInset: 1.5`, and the average kcal in the center.
  5. Weight card (`diaryChartSurface`): faint `PointMark`s, a bold `LineMark` trend, an `AreaMark`, a dashed goal `RuleMark`, and a start → goal bar.
  6. Calendar: a `RectangleMark` grid. Week and Month show the current month; 3M and Year show weeks as columns.
  7. Calories card.
  8. Burn card (`diaryTintBurn`) with a line and an `AreaMark` band.
  9. Top foods (`diaryTintFoods`, top 4).
  10. Workouts and Goals rows.

  Every card has a text summary for VoiceOver. Charts reflow at accessibility sizes. Placeholder copy: "Log N more days to see your burn", "Weigh in on N more days to see your trend", "Add a goal weight to see how far is left".
- [ ] **Step 4: Run** `ProgressInsightsTests`, then build and run on the reserved simulator. Screenshot the Week and Year ranges in light and dark mode at the largest accessibility size and compare against the mockup.
- [ ] **Step 5: Commit** `feat(progress): chart-first Progress tab`.

### Task 6: Detail screens

**Files:**
- Create: `ios/Mivu/Progress/ProgressDetailViews.swift`
- Modify: `ios/Mivu/Progress/ProgressView.swift` (`weightDetail`, `workoutList` restyle; wire `NavigationLink`s)

**Interfaces:**
- Consumes: the card charts from Task 5, `progressForDisplay`, `topFoods`.
- Produces: `ProgressCaloriesDetail`, `ProgressMacrosDetail`, `ProgressCalendarDetail`, `ProgressBurnDetail`, and `ProgressFoodsDetail` (all foods, `limit: 200`).
- Each detail screen pages back by whole range windows: an "Earlier" control reloads `progressForDisplay(endingOn: previousStart − 1 day, days: range.days)`. It stops when a window has no tracking days.
- Charts use `chartScrollableAxes(.horizontal)` and `chartXSelection`.

- [ ] **Step 1: Write a failing UI test** `ProgressUITests.testEachCardOpensItsDetail`. Tap `progressCalories`, `progressMacros`, `progressCalendar`, `progressBurn` and `progressTopFoods` in turn. Assert each detail's navigation title ("Calories", "Macros", "Calendar", "Estimated burn", "Top foods") and go back each time.
- [ ] **Step 2: Run to verify failure.**
- [ ] **Step 3: Implement.** Weight and Workouts keep their ledger, editing, Ask Pip and paging, and are only restyled.
- [ ] **Step 4: Run** that test plus the existing `testWeight…`/`testWorkout…` methods in `ProgressUITests`.
- [ ] **Step 5: Commit** `feat(progress): detail screens for every card`.

### Task 7: Migrate UI tests, verify, review

**Files:**
- Modify: `ios/MivuUITests/ProgressUITests.swift`, `ios/MivuUITests/SummaryCardsUITests.swift:62-63`, `ios/MivuUITests/RootTabNavigationUITests.swift:23-30`
- Create: `docs/verification/2026-10-23-progress-insights.md`

- [ ] **Step 1: Migrate the identifiers.**
  - `reportDaily`, `reportWeekly` and `reportMonthly` become `app.segmentedControls["progressRange"].buttons["Week" | "Month"]`.
  - Daily goal-summary assertions (`progressGoalSummary`) move to the Today tab's equivalent, or are dropped with a one-line note in the verification record.
  - `progressCoverage` and `openDiaryForCoverage` become the `progressCalendar` card. Its placeholder keeps an "Open Diary" button with id `openDiaryForCoverage`.
- [ ] **Step 2: Run the focused suites:** the units `ProgressInsightsTests`, `ProgressAnalyticsTests`, `DiaryProjectionIntegrationTests` and `CoachStoreTests`, and the UI tests `ProgressUITests`, `SummaryCardsUITests` and `RootTabNavigationUITests`. Record the counts.
- [ ] **Step 3: Smoke:** `python3 scripts/ci/smoke.py --simulator-id <reserved-UUID>` → PASS.
- [ ] **Step 4: Run `/ponytail:ponytail-review`** on the branch and fix the blocking findings.
- [ ] **Step 5: Write the verification record** (SHA, simulator, counts, screenshots, blocked gates), then commit `test(progress): migrate Progress UI tests and record verification`.
