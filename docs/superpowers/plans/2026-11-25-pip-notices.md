# Pip Notices Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Once a day at most, Pip says one true observation about the person's own diary in the Coach bubble and the morning card, with an optional one-tap offer.

**Architecture:** A pure detector turns 30 daily reports and 7 days of meals into ordered candidates; a pure chooser applies the once-a-day and rest rules against a small per-profile log in `UserDefaults`. `DiaryViewModel` loads today's notice once per waking day and the existing surfaces (`PipLine`, `QuickPrompts`, `MorningCheckInCard`, `CoachEngine`) each take it as one extra input.

**Tech Stack:** Swift 6, SwiftUI, iOS 26, Swift Testing (`import Testing`), XCUITest. No new dependency.

**Spec:** `docs/superpowers/specs/2026-11-25-pip-notices-design.md`

## Setup

- Work on a new branch `feat/pip-notices` from `origin/main` (`7247c348` or newer), in its own worktree. The checkout this plan was written in sits on an old branch; do not build there.
- Copy this plan and the spec into the new branch and commit them first: `docs(coach): Pip notices design and plan`.
- Run focused tests with XcodeBuildMCP, scheme `Mivu`, using `-only-testing:` for the suites each task names. Line numbers below are from `7247c348`; find the symbol if they moved.

## Global Constraints

- `AGENTS.md` applies: failing test first, platform APIs first, minimal Swift, Conventional Commit titles, no mention of AI tools in commits or the PR.
- Every number Pip says is a count the detector produced. No sentence is written by the model.
- "Near" is `ProgressBand.near`. "Off" is `.off` or `.farOff`. The band is `ProgressBand.of(kcal: report.foodTotals?.kcal, target: report.goal?.targets.kcal)`, the same call Progress makes. Only reports with `status == .closed` count.
- Nothing fires until `loggedDayCount` is at least 14.
- At most one notice per waking day per profile; a kind rests 7 days; at most two non-win notices in any 7 days.
- Forbidden in copy: "bad", "cheating", "failed", streak counts, advice to skip meals or eat below target.
- Whole localized sentences per case in `ios/Mivu/Localizable.xcstrings` for `en`, `es`, `ru`, `he`; never a word slotted into a sentence. Gender-neutral wording.
- Coach paths stay on bounded owner queries; no full `DiarySnapshot`. Nothing is added to the persisted capture context or manifest.
- No new stored diary record type, no new network call, no notification.
- Touch targets at least 44 points; VoiceOver reads the notice and the offer; Dynamic Type and Reduce Motion respected.

## Review Focus

1. **Profile switched while the notice loads.** Profile A's observation must never show under profile B. Test in Task 3.
2. **Days without a calorie target or with unknown calories.** They are neither near nor off and must not crash or count. Test in Task 1.
3. **A meal eaten in another time zone.** Its clock time is read in the meal's own zone (`meal.timeZoneID`), not the profile's. Test in Task 1.
4. **The day rolls over with the app open.** Yesterday's notice must not carry into the new day. Test in Task 3.
5. **The switch is turned off mid-day.** The notice leaves the bubble and the card at once, and Coach is no longer told about it. Test in Task 3.

## File Structure

| File | Responsibility |
| --- | --- |
| Create `ios/Mivu/Progress/PipNotices.swift` | `PipNotice`, the detector, the chooser, the log store, copy and offers |
| Create `ios/Mivu/Progress/PipNoticeUITestFixture.swift` | DEBUG launch-argument fixture |
| Create `ios/MivuTests/PipNoticesTests.swift` | Detector, chooser, log and copy tests |
| Create `ios/MivuUITests/PipNoticeUITests.swift` | One end-to-end UI test |
| Modify `ios/Mivu/Diary/DiaryViewModel.swift` | Load and expose today's notice |
| Modify `ios/Mivu/Diary/DaySettingsSection.swift` | The off switch |
| Modify `ios/Mivu/Coach/PipLine.swift`, `QuickPrompts.swift`, `CoachView.swift` | Bubble and offer chip |
| Modify `ios/Mivu/Diary/MorningCheckInCard.swift`, `TodayView.swift` | Morning card line |
| Modify `ios/Mivu/Coach/CoachEngine.swift`, `CoachViewModel.swift` | Coach knows what Pip said |
| Modify `ios/Mivu/Localizable.xcstrings` | Translations |

---

### Task 1: Detector

**Files:**
- Create: `ios/Mivu/Progress/PipNotices.swift`
- Test: `ios/MivuTests/PipNoticesTests.swift`

**Interfaces:**
- Consumes: `DailyProgress`, `ProgressBand`, `ProgressInsights.days(from:to:)`, `RecentMeal`, `MealReadModel` (`eatenAt`, `capturedAt`, `timePrecision`, `timeZoneID`).
- Produces:

```swift
enum PipNotice: Codable, Equatable, Sendable {
    case welcomeBack
    case bestWeek(near: Int, days: Int)
    case betterWeek(near: Int, before: Int)
    case weekendDrift(over: Bool)
    case weekdayDrift(weekday: Int, over: Bool)   // Calendar weekday, 1 = Sunday
    case lateDinners(count: Int)
    case lateFirstMeal(count: Int)
    case proteinShort(short: Int, days: Int)
    var kind: String { get }     // the case name without values, e.g. "weekdayDrift"
    var isWin: Bool { get }      // welcomeBack, bestWeek, betterWeek
}

struct PipNoticeInput: Sendable {
    var today: String             // yyyy-MM-dd of the active waking day
    var reports: [DailyProgress]  // 30 days ending yesterday, oldest first
    var meals: [RecentMeal]       // saved meals of the 7 days ending yesterday
    var loggedDays: Int           // all-time
    var calendar: Calendar        // profile time zone; its locale decides the weekend
}

enum PipNotices {
    /// In order of preference. Empty when nothing qualifies.
    static func candidates(_ input: PipNoticeInput) -> [PipNotice]
}
```

Rules, with "week 0" the last 7 reports and weeks 1 to 3 the three 7-day blocks before it:

| Case | Fires when |
| --- | --- |
| `welcomeBack` | No closed report, or `days(from: newest closed date, to: today) >= 4`. When it fires it is the only candidate. |
| `bestWeek(near, days)` | `near` = near days in week 0, `days` = closed days in week 0; `near >= 4`, `near` greater than the near count of each of weeks 1 to 3, and weeks 1 to 3 hold at least 10 closed days together. |
| `betterWeek(near, before)` | `near >= 4`, `near >= before + 2`, and week 1 has at least 4 closed days. |
| `weekendDrift(over)` | Group weekend days (`calendar.isDateInWeekend`) of the last 28 reports into weekends. A weekend is off when the sum of kcal over its closed days differs from the sum of their targets by more than 20%. At least 3 of the last 4 weekends are off in the same direction, fewer than one third of closed weekdays are off, and today or tomorrow is a weekend day. |
| `weekdayDrift(weekday, over)` | The reports 7, 14, 21 and 28 days before today: at least 3 are closed and off in the same direction. `weekday` is today's. |
| `lateDinners(count)` | Over closed days in week 0 that have a timed meal: the last timed meal is at 21:30 or later, or falls on a calendar date after its waking day. `count >= 3`. |
| `lateFirstMeal(count)` | Same days: the first timed meal is at 13:00 or later. `count >= 4`. |
| `proteinShort(short, days)` | Last 14 reports, closed days with known protein and a protein target above 0: `days >= 5`, `short` = days under 80% of target, `short * 10 >= days * 6`. |

A meal is timed when `timePrecision == .exact`, or `timePrecision == nil` and `abs(capturedAt - eatenAt) <= 2 hours`. Read its clock in `meal.timeZoneID` when set, else the calendar's zone.

Return order: `welcomeBack`, `bestWeek`, `betterWeek`, `weekendDrift`, `weekdayDrift`, `lateDinners`, `lateFirstMeal`, `proteinShort`. Return `[]` when `loggedDays < 14`.

- [ ] **Step 1: Write the failing tests** in `PipNoticesTests.swift`. Build reports with a helper `day(_ offset: Int, kcal: Double?, target: Double? = 2000, protein: Double? = nil, proteinTarget: Double? = nil, status: DayStatus? = .closed)` relative to `today = "2026-11-26"` (a Thursday), and meals with the helper style of `QuickPromptsTests`.

```swift
@Test func silentBelowFourteenLoggedDays()          // loggedDays 13, any data -> []
@Test func welcomeBackAfterThreeDaysAway()          // newest closed 2026-11-22 -> [.welcomeBack]; 2026-11-23 -> no welcomeBack
@Test func bestWeekNeedsFourNearAndBeatsEarlierWeeks() // 6 near vs 3,4,2 -> .bestWeek(near: 6, days: 7); 6 vs 6 -> absent; earlier weeks with 9 closed days -> absent
@Test func betterWeekNeedsTwoMore()                 // 5 vs 3 -> .betterWeek(near: 5, before: 3); 5 vs 4 -> absent
@Test func weekdayDriftAtThreeOfFour()              // Thursdays 2600 of 2000 on 3 of 4 -> .weekdayDrift(weekday: 5, over: true); 2 of 4 -> absent; 2 over + 1 under -> absent
@Test func weekendDriftFollowsTheCalendarRegion()   // same data: he_IL off on Fri+Sat fires, en_US does not; shown only when today or tomorrow is a weekend day
@Test func weekendDriftNeedsCalmWeekdays()          // a third or more of weekdays off -> absent
@Test func lateDinnersAtThree()                     // last meals 21:30, 22:10, 00:40 next date -> .lateDinners(count: 3); 21:29 does not count
@Test func lateFirstMealAtFour()                    // first meals at 13:00 on 4 days -> .lateFirstMeal(count: 4); 3 days -> absent
@Test func untimedMealsAreIgnored()                 // .dateOnly, and nil precision captured 3 h after eatenAt -> not counted
@Test func mealClockUsesTheMealsZone()              // 20:00 UTC eaten in Asia/Tokyo, profile zone UTC -> counts as a late dinner
@Test func proteinShortAtSixtyPercent()             // 3 of 5 under 80% -> .proteinShort(short: 3, days: 5); 2 of 5 -> absent; 4 known days -> absent
@Test func daysWithoutTargetOrCaloriesAreNeutral()  // target nil or kcal nil: never near, never off, no crash
@Test func preferenceOrder()                        // data firing bestWeek, weekdayDrift and proteinShort returns them in that order
```

- [ ] **Step 2: Run** `-only-testing:MivuTests/PipNoticesTests`. Expected: build fails, `PipNotices` not found.
- [ ] **Step 3: Implement** `PipNotice`, `PipNoticeInput` and `PipNotices.candidates` in `PipNotices.swift` as one small private function per rule.
- [ ] **Step 4: Run** the same suite. Expected: all pass.
- [ ] **Step 5: Commit** `feat(progress): detect diary patterns for Pip`

### Task 2: Choosing, the log, and the words

**Files:**
- Modify: `ios/Mivu/Progress/PipNotices.swift`
- Test: `ios/MivuTests/PipNoticesTests.swift`

**Interfaces:**
- Consumes: `PipNotice` from Task 1.
- Produces:

```swift
struct PipNoticeLog: Codable, Equatable, Sendable {
    struct Shown: Codable, Equatable, Sendable { var localDate: String; var notice: PipNotice; var offerTapped = false }
    var scanned: String?          // last waking day the detector ran for
    var shown: [Shown] = []       // newest last; entries older than 30 days are dropped on save
}

struct PipNoticeStore {
    static let enabledKey = "pipNoticesEnabled"   // Bool, absent means on
    let defaults: UserDefaults
    func log(for profileID: UUID) -> PipNoticeLog          // unreadable data reads as empty
    func save(_ log: PipNoticeLog, for profileID: UUID)
}

extension PipNotices {
    /// The first candidate allowed today, given what was shown before.
    static func choose(_ candidates: [PipNotice], shown: [PipNoticeLog.Shown], today: String) -> PipNotice?
}

extension PipNotice {
    var text: String { get }                                // localized sentence
    var offer: (title: String, message: String)? { get }   // nil for wins and welcomeBack
}
```

`PipNoticeStore` follows `TimeZoneStateStore` in `ios/Mivu/Diary/TimeZoneSync.swift:64`; key `"pipNotices." + profileID.uuidString`.

`choose` skips a candidate whose `kind` was shown fewer than 7 days before `today`, and skips non-wins when two non-wins were shown in the 6 days before `today`.

English copy, pinned by tests:

| Case | `text` | `offer.title` | `offer.message` |
| --- | --- | --- | --- |
| `welcomeBack` | Good to see you again. Pick up from today? | | |
| `bestWeek(6, 7)` | 6 of 7 days near target. Your best week this month! | | |
| `betterWeek(5, 3)` | 5 days near target this week, up from 3. | | |
| `weekendDrift(over: true)` | Weekends tend to run over for you. | Plan a lighter weekend | My weekends usually run over my calorie target. Help me plan a lighter one. |
| `weekendDrift(over: false)` | Weekends tend to come in well under for you. | Ideas to fill the weekend | My weekends usually come in well under my calorie target. Give me easy ideas to reach it. |
| `weekdayDrift(5, over: true)` | Thursdays usually run over for you. | Plan today with me | This day of the week usually runs over my calorie target. Help me plan today. |
| `weekdayDrift(5, over: false)` | Thursdays usually come in well under for you. | Easy ideas for today | This day of the week usually comes in well under my calorie target. Give me easy ideas to reach it. |
| `lateDinners(3)` | Dinner landed after 9:30 pm on 3 days this week. | Earlier dinner ideas | My dinners have been running late this week. Give me an idea for an earlier dinner. |
| `lateFirstMeal(4)` | Your first meal came after 1 pm on 4 days this week. | A quick earlier option | My first meal has been coming late this week. Suggest a quick earlier option. |
| `proteinShort(9, 12)` | Protein came in short on 9 of your last 12 logged days. | Easy ways to add protein | My protein has been short of my target lately. Give me easy ways to add some. |

`weekdayDrift` text is a `switch` over weekday 1 to 7 and direction: fourteen whole sentences, one `String(localized:)` each.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func kindRestsSevenDays()        // proteinShort shown 2026-11-20, today 11-26 -> skipped; today 11-27 -> chosen
@Test func twoNonWinsPerSevenDays()    // lateDinners 11-21 and proteinShort 11-23 shown, today 11-26: [.weekdayDrift, .bestWeek] -> .bestWeek
@Test func nothingAllowedReturnsNil()
@Test func logRoundTripsAndDropsOldEntries()  // save then read equal; an entry 31 days old is gone
@Test func unreadableLogReadsAsEmpty()        // garbage Data under the key -> PipNoticeLog()
@Test func englishCopy()                      // every row of the table above, text and offer
@Test func winsCarryNoOffer()
@Test func copyAvoidsBlame()           // no text or offer contains "bad", "cheat", "fail", "streak"
```

Use `UserDefaults(suiteName: UUID().uuidString)!` for the store tests.

- [ ] **Step 2: Run** the suite. Expected: build fails on the new names.
- [ ] **Step 3: Implement** the log, store, `choose`, `text` and `offer`.
- [ ] **Step 4: Run** the suite. Expected: all pass.
- [ ] **Step 5: Commit** `feat(progress): choose and word Pip's daily notice`

### Task 3: Load today's notice, with an off switch

**Files:**
- Modify: `ios/Mivu/Diary/DiaryViewModel.swift` (next to `loadMorningRecap`, line 277)
- Modify: `ios/Mivu/Diary/DaySettingsSection.swift`
- Modify: `ios/Mivu/Diary/TodayView.swift:211`, `ios/Mivu/Coach/CoachView.swift:259`
- Create: `ios/Mivu/Progress/PipNoticeUITestFixture.swift`
- Test: the suite that already tests `DiaryViewModel` loading (find it by `loadMorningRecap`); add `ios/MivuTests/PipNoticeLoadingTests.swift` if none fits

**Interfaces:**
- Consumes: Tasks 1 and 2; `store.loggedDayCount(expectedProfileID:)`, `store.progressForDisplay(endingOn:days:expectedProfileID:)` with `days: 30` (use `.dailyReports`), `store.recentMeals(from:to:expectedProfileID:)`, `ProgressAnalytics.window(endingOn:days:offset:zone:)`, the view model's `preferences` defaults.
- Produces, on `DiaryViewModel`:

```swift
/// What Pip noticed for the active day, whether or not it is still on screen. Coach is told this one.
private(set) var todaysPipNotice: PipNotice?
/// The notice while it should show: no meal saved today and the offer not tapped.
var visiblePipNotice: PipNotice? { get }
func loadPipNotice() async
func markPipOfferTapped()
```

Behavior of `loadPipNotice`:
1. Clear and return when the switch (`PipNoticeStore.enabledKey`) is off, or there is no active day or profile.
2. If the log has an entry for the active day's `localDate`, use it. If `log.scanned` equals that date, there is nothing today.
3. Otherwise read the three queries off the main actor, build `PipNoticeInput` with a Gregorian calendar in the profile zone and `locale = .current`, call `candidates` then `choose`, save the log with `scanned` set and the chosen entry appended.
4. Before assigning, check the selection token and the active day are unchanged, as `refreshRecentMeals` does (`CoachViewModel.swift:731`).
5. A failed read leaves the notice nil and does not set `scanned`.

`markPipOfferTapped` sets `offerTapped` on today's entry and saves.

Call `loadPipNotice()` from the same `.task` that calls `loadMorningRecap()` in `TodayView`, and from the `.task(id: coach.diary.changeGeneration)` in `CoachView`.

Settings: under "Morning check-in" in `DaySettingsSection`, `Toggle` bound to `@AppStorage(PipNoticeStore.enabledKey) = true`, label `"Pip's observations"`, system image `sparkles`, `minHeight: 44`, identifier `pipNoticesToggle`. Turning it off clears the visible notice at once.

Fixture: `PipNoticeUITestFixture.notice` returns `.proteinShort(short: 9, days: 12)` when `DiaryLaunch.isUITest` and the launch argument `--pip-notice-fixture` is present; `loadPipNotice` uses it instead of scanning. Model it on `QuickPromptsUITestFixture`.

- [ ] **Step 1: Write the failing tests**, importing a synthetic 21-day profile through `store.importProfile` (pattern: `QuickPromptsUITestFixture.snapshot`) with protein under 80% of target on most days:

```swift
@Test func loadsOnceADay()                 // first load sets .proteinShort; a second load does not query again and returns the same
@Test func savedMealHidesButCoachStillKnows() // after a meal today: visiblePipNotice == nil, todaysPipNotice != nil
@Test func offerTapHidesIt()
@Test func switchOffClearsBoth()           // enabledKey false -> both nil (Review Focus 5)
@Test func newDayDoesNotCarryYesterdaysNotice() // start the next day -> not yesterday's entry (Review Focus 4)
@Test func profileSwitchDuringLoadAssignsNothing() // switch selection before the load resumes (Review Focus 1)
```

- [ ] **Step 2: Run** the suite. Expected: build fails on `loadPipNotice`.
- [ ] **Step 3: Implement** the view model members, the two call sites, the toggle and the fixture.
- [ ] **Step 4: Run** the suite plus `PipNoticesTests`. Expected: all pass.
- [ ] **Step 5: Commit** `feat(diary): load Pip's daily notice with a settings switch`

### Task 4: Pip says it in Coach

**Files:**
- Modify: `ios/Mivu/Coach/PipLine.swift`, `ios/Mivu/Coach/QuickPrompts.swift`, `ios/Mivu/Coach/CoachView.swift` (lines 447, 739, 833, 859)
- Test: `ios/MivuTests/PipLineTests.swift`, `ios/MivuTests/QuickPromptsTests.swift`

**Interfaces:**
- Consumes: `visiblePipNotice`, `markPipOfferTapped()`, `PipNotice.text`, `PipNotice.offer`.
- Produces: `PipLine.current(..., tip: Bool = false, notice: String? = nil)`; `QuickPromptInput.notice: PipNotice?`; chip id `"pip.notice"`.

`PipLine`: after the `tip` check, `if !mealsLogged, let notice { return .say(notice) }`. Everything above it keeps its priority.

`QuickPrompts.choose`: when `input.notice?.offer` exists and `input.todaysMeals` is empty, insert `QuickPrompt(id: "pip.notice", title: offer.title, symbol: "sparkles", action: .send(offer.message))` at index 0 after the hidden filter and the reorder, before `prefix(input.limit)`.

`CoachView`: pass `notice: coach.diary.visiblePipNotice?.text` to `PipLine.current` and `notice: coach.diary.visiblePipNotice` to `QuickPromptInput`. In the `.send` branch (line 859) call `coach.diary.markPipOfferTapped()` when the prompt id is `"pip.notice"`. The hide action (line 833) must not be offered for that id.

- [ ] **Step 1: Write the failing tests**

```swift
// PipLineTests
@Test func noticeReplacesThePreMealGreeting()   // notice "X": hour 8 -> .say("X"); chips: true -> .say("X")
@Test func noticeYieldsToEverythingElse()       // processing, !connected, recovery, typing, tip, mealsLogged: unchanged from today
// QuickPromptsTests
@Test func offerChipLeadsTheRow()               // first chip id "pip.notice", title and .send(message) from the offer
@Test func offerChipIgnoresHiddenAndCountsTowardLimit() // hidden contains "pip.notice": still first; limit 2 -> 2 chips
@Test func noOfferChipForWinsOrAfterAMeal()
```

- [ ] **Step 2: Run** `PipLineTests` and `QuickPromptsTests`. Expected: build fails on the `notice` parameter.
- [ ] **Step 3: Implement** the three changes.
- [ ] **Step 4: Run** both suites. Expected: all pass, including every existing test.
- [ ] **Step 5: Commit** `feat(coach): Pip says his notice and offers a next step`

### Task 5: The morning card

**Files:**
- Modify: `ios/Mivu/Diary/MorningCheckInCard.swift`, `ios/Mivu/Diary/TodayView.swift:752`
- Test: covered by the UI test in Task 7

**Interfaces:**
- Consumes: `visiblePipNotice`, `markPipOfferTapped()`.
- Produces: `MorningCheckInCard(..., notice: PipNotice? = nil, onOffer: ((String) -> Void)? = nil, onDismiss:)`.

In the full `card` only, under the recap and above the weigh-in: the notice text (`.subheadline`, `Color.diaryText`, identifier `morningPipNotice`) and, when there is an offer, a bordered capsule button with `offer.title`, `minHeight: 44`, identifier `morningPipOffer`, calling `onOffer(offer.message)`. The line shows even when `showsRecap` is false. The compact card is unchanged.

`TodayView` passes `notice: model.visiblePipNotice` and an `onOffer` that marks the offer tapped, opens Coach by the route Today already uses, and sends the message through the same path the `.send` chip takes. If Today can only prefill Coach and not send, stop and report before choosing a workaround.

- [ ] **Step 1: Implement** the two parameters, the row and the `TodayView` wiring.
- [ ] **Step 2: Build** the `Mivu` scheme. Expected: succeeds; `PipLineTests`, `QuickPromptsTests`, `PipNoticesTests` still pass.
- [ ] **Step 3: Commit** `feat(today): show Pip's notice in the morning check-in`

### Task 6: Coach knows what Pip said

**Files:**
- Modify: `ios/Mivu/Coach/CoachEngine.swift` (init, the tail developer message at line 46, `sources` at line 96), `ios/Mivu/Coach/CoachViewModel.swift:505`
- Test: `ios/MivuTests/CoachEngineTests.swift`

**Interfaces:**
- Consumes: `todaysPipNotice?.text`.
- Produces: `CoachEngine.init(..., pipNotice: @escaping @Sendable () async -> String? = { nil })`.

When the closure returns text, append to the per-turn tail developer message, before `Context:`: `Earlier today Pip told the person: "<text>" It was computed by the app from their diary. ` Add the same text to `sources`, so a reply that repeats its numbers passes the existing number check. `stableRules` is not touched, so the cacheable prefix is unchanged. `CoachViewModel` passes a closure reading `diary.todaysPipNotice?.text` on the main actor.

- [ ] **Step 1: Write the failing tests**, using the fixtures already in `CoachEngineTests`:

```swift
@Test func tailMessageCarriesPipsNotice()      // closure returns "Protein came in short on 9 of your last 12 logged days." -> last developer message contains it; stableRules message unchanged
@Test func noNoticeLeavesTheInputUnchanged()   // default closure -> input equals today's input
@Test func replyMayRepeatTheNoticeNumbers()    // a reply quoting "9 of your last 12" is accepted, not sent back for re-answer
```

- [ ] **Step 2: Run** `CoachEngineTests`. Expected: build fails on `pipNotice:`.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `CoachEngineTests`. Expected: all pass.
- [ ] **Step 5: Commit** `feat(coach): tell Coach what Pip noticed today`

### Task 7: Translations, UI test, review

**Files:**
- Modify: `ios/Mivu/Localizable.xcstrings`
- Create: `ios/MivuUITests/PipNoticeUITests.swift`

- [ ] **Step 1: Translate** every new string into `es`, `ru` and `he`. Sentences with a count need plural variations where the language requires them (Russian, Hebrew). Keep each notice to one short sentence and each offer title to about four words. No gendered forms.
- [ ] **Step 2: Run** `python3 -m unittest discover scripts/ci` and the catalog check in `scripts/ci/languages.py`. Expected: pass, no missing rows.
- [ ] **Step 3: Write the UI test** `testPipNoticeInCoachAndMorningCard`, launched with `["--diary-ui-test", id, "--coach-ui-test", "--coach-inference-fixture", "--quick-prompts-fixture", "--quick-prompts-hour", "9", "--pip-notice-fixture"]`:
  - Today shows `morningPipNotice` with "Protein came in short on 9 of your last 12 logged days." and `morningPipOffer` at least 44 points tall.
  - In Coach, `coachCompanionStrip` contains the same sentence and the first chip reads "Easy ways to add protein".
  - Tapping the chip sends "My protein has been short of my target lately. Give me easy ways to add some." as the newest message; the bubble no longer shows the notice and the chip is gone.
  - After relaunch with the same id, the notice does not come back that day.
- [ ] **Step 4: Run** `-only-testing:MivuUITests/PipNoticeUITests` plus the existing quick-prompt and morning check-in UI tests this change touches. Expected: pass. Do not run the whole UI suite.
- [ ] **Step 5: Screenshots.** Capture Today and Coach with the notice in light and dark, English and Hebrew, at default and one accessibility text size.
- [ ] **Step 6: Review.** Run the `ux-ui-reviewer` and `senior-qa` agents on the screenshots and the simulator build, then Ponytail Review on the branch. Fix blocking findings.
- [ ] **Step 7: Commit** `feat(coach): translate Pip's notices and cover them end to end`, then open the PR `feat(coach): Pip notices patterns in your diary`. In the body record the tested SHA, simulator and OS, and the pass counts of each suite named above.

## Not in this plan

Android, notifications, a weekly note, remembering facts the person tells Pip, usual-meal learning, weight-trend notices, new Pip artwork.
