# Coach Quick Prompts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Coach's three fixed starter chips with a context-aware chip row in the composer. The row offers re-log, log, follow-up and question chips. Re-logs copy meals exactly through a new Coach tool. The "See today" and "See progress" follow-ups are removed.

**Architecture:**
- A pure function `QuickPrompts.choose(_:)` turns a snapshot of the day into at most 4 chips. It has unit tests and no UI.
- A bounded diary query supplies the last 14 days of saved meals, for re-log sources.
- `CoachView` renders the row inside a new composer tray. Fill chips write the draft; re-log chips also set a `.meal` reply quote.
- A new `copy_meal` tool lets Coach log the quoted meal's items unchanged, through the normal food write path.

**Tech Stack:** SwiftUI (iOS 26 SDK), Swift Testing (`@Test`, `#expect`) in `MivuTests`, XCTest UI tests in `MivuUITests`, XcodeBuildMCP for every build and test.

**Spec:** `docs/superpowers/specs/2026-11-17-coach-quick-prompts-design.md`. Read it first. Mockup: `docs/superpowers/specs/assets/2026-11-17-coach-quick-prompts-mockup.html`.

**Branch:** `feat/coach-quick-prompts`, in the worktree `../mivu-coach-quick-prompts`, based on PR #145. After #145 merges, run `git rebase origin/main` before opening the PR.

## Global Constraints

- English-only MVP. Every new string uses `String(localized:)` and is added to `ios/Mivu/Localizable.xcstrings`.
- Chips are 36 pt visible with a 44 pt minimum hit target. Supports Dynamic Type, VoiceOver and Reduce Motion.
- At most 4 chips, or 2 when the window is wide (open Duo sideways), short (height < 700 pt, closed Duo), or at Dynamic Type `.accessibility3` and above.
- Chip titles are 18 characters or fewer. A send chip is always among the first two. No chips means no row.
- Send chips send only read-only questions. Diary changes are fill chips, and nothing is sent until the user taps Send.
- No emoji and no gradients. The tray is the only material layer, and chips use the `diarySurface` fill (no glass on glass).
- Rule-based chips only. Never ask the model to choose them.
- Ordinary Coach paths use bounded owner queries. Do not rebuild a complete `DiarySnapshot`.
- Never commit secrets. Commit messages are Conventional Commits and never mention AI tools.
- Run the tests with XcodeBuildMCP (simulator test, `-testPlan Mivu -only-testing:<suite>`, `-parallel-testing-enabled NO`). Record the source SHA.

**How the plan reconciles the spec with the code.** These are planning calls:
- The spec's "existing composer glass tray" doesn't exist yet. Task 5 creates it as a material tray, so the round glass mic/send buttons stay the only glass.
- The spec's closed-Duo header change needs no work. Coach's title is already `.inlineLarge`, and the day/kcal chip (`coachDate`) already sits beside Pip rather than in a top date line.
- The spec's mention of `CoachViewportMode` is wrong. That type covers history paging. Use `isWideLayout` and the measured window height.

## Review Focus

1. **A meal deleted or edited after its chip was built.** Tapping the re-log chip must not log stale items. `copy_meal` checks `expected_revision`, and a mismatch makes Coach fall back to `log_food`. This is pinned in Task 3.
2. **Midnight and day rollover with yesterday's follow-ups.** A follow-up set for an exchange from another waking day must not show. This is pinned in Task 1 (`followUpsNeedTodaysExchange`).
3. **Hidden chips leaving fewer than two.** Hiding must not empty the send slot or reorder past the limit. This is pinned in Task 1 (`hiddenChipsAreSkippedBeforeTheLimit`).
4. **No kcal target and no history**, as for a new user right after onboarding is skipped. The row still offers "Log {slot}…" and never shows a question that needs a target. This is pinned in Task 1 (`newUserWithoutTargetGetsLoggingChipsOnly`).
5. **The keyboard up on the closed Duo.** The row stays at 2 chips and above the keyboard, and the latest reply stays visible. This is pinned in Task 5 (Duo UI test plus a screenshot).

---

### Task 1: The chip-choosing function

**Files:**
- Create: `ios/Mivu/Coach/QuickPrompts.swift`
- Test: `ios/MivuTests/QuickPromptsTests.swift`

**Interfaces:**
- Produces:
```swift
struct RecentMeal: Equatable, Sendable { var localDate: String; var meal: MealReadModel }

enum MealSlot: String, Sendable { case breakfast, lunch, dinner
    static func at(hour: Int) -> MealSlot          // <11 breakfast, 11..<16 lunch, else dinner
    var title: String                              // "breakfast" / "lunch" / "dinner" (localized, lowercase)
}

struct QuickPrompt: Equatable, Identifiable, Sendable {
    enum Action: Equatable, Sendable {
        case send(String)
        case fill(String)
        case relog(mealID: UUID, text: String, excerpt: String)
    }
    var id: String          // stable hide key, see table below
    var title: String
    var symbol: String?     // SF Symbol; nil for re-log (it shows the meal thumbnail)
    var kcal: Int?          // re-log only
    var photo: DiaryPhotoReference?   // re-log only
    var action: Action
    var sends: Bool { if case .send = action { true } else { false } }
}

enum QuickPromptLatest: Equatable, Sendable {
    case meal(id: UUID, committedRevision: Int, localDate: String)
    case weight(localDate: String)
    case workout(localDate: String)
}

struct QuickPromptInput: Sendable {
    var hour: Int
    var today: String; var yesterday: String          // waking-day local dates
    var todaysMeals: [MealReadModel]                  // today's read model meals
    var recent: [RecentMeal]                          // saved meals, yesterday back 14 days, newest first
    var kcalEaten: Double?; var kcalTarget: Double?
    var proteinEaten: Double?; var proteinTarget: Double?
    var weighedToday: Bool; var morningCardShowing: Bool
    var latest: QuickPromptLatest?
    var limit: Int                                    // 4, or 2 (see Global Constraints)
    var wide: Bool
    var hidden: Set<String>
}

enum QuickPrompts { static func choose(_ input: QuickPromptInput) -> [QuickPrompt] }
```

**Chip table (ids, titles, symbols, actions).** Titles are copied from the spec. `{slot}` is `MealSlot.title`.

| id | title | symbol | action |
|---|---|---|---|
| `relog` | "Same {slot}" (source from yesterday) / "Usual {slot}" (frequent) | — | `.relog(mealID, text: "For {slot} I had {items}", excerpt: "{title} · {kcal} kcal")` |
| `ask.yesterday` | "How was yesterday?" | `chart.bar.fill` | `.send` |
| `ask.calories` | "Calories left?" | `chart.bar.fill` | `.send` |
| `ask.balanced` | "Was it balanced?" | `leaf.fill` | `.send` (replaces `ask.calories` when `wide`) |
| `ask.protein` | "Protein ideas?" | `leaf.fill` | `.send` |
| `ask.trend` | "Weekly trend?" | `chart.line.uptrend.xyaxis` | `.send` |
| `log.slot` | "Log {slot}…" | `fork.knife` | `.fill("For {slot} I had ")` |
| `log.snack` | "Log a snack…" | `fork.knife` | `.fill("For a snack I had ")` |
| `log.weight` | "Log weight…" | `scalemass` | `.fill("My weight this morning is ")` |
| `fix.portion` | "Smaller portion…" | `minus.circle` | `.fill("Make {meal slot} a smaller portion: ")` |
| `add.drink` | "Add a drink…" | `cup.and.saucer` | `.fill("Add a drink to {meal slot}: ")` |

**Rules, in order:**
- **Moment question:**
  - before 11:00 → `ask.yesterday`;
  - from 16:00, when protein has a target and is below 70% of it → `ask.protein`;
  - otherwise, with a kcal target → `ask.calories` (or `ask.balanced` when `wide`);
  - otherwise none.
- **Valid `latest`:**
  - `.meal` is valid when its `localDate == today` and `todaysMeals` still has that id at `committedRevision`. It gives `[ask.calories|ask.balanced, fix.portion, add.drink]`, where `{meal slot}` is `MealSlot.at(hour:)` of that meal's `eatenAt`.
  - `.weight(today)` gives `[ask.trend]` followed by the slot chips.
  - `.workout(today)` gives `[ask.calories|ask.balanced]` followed by the slot chips.
  - Anything else is ignored.
- **Slot chips** (current slot):
  - Slot not yet logged (no meal in `todaysMeals` whose `eatenAt` hour falls in the slot): `[relog?, moment question?, log.slot, log.weight?]`.
  - Slot logged: `[moment question?, log.snack, log.weight?]`.
  - `log.weight` appears only when `!weighedToday && !morningCardShowing`.
- **Re-log source:**
  - First try yesterday's latest saved meal in the slot that has items → "Same {slot}".
  - Otherwise, among `recent` in the slot, group by the sorted, lowercased, trimmed item names. Take the largest group with at least 2 meals (on a tie, the newest group) and its newest meal → "Usual {slot}".
  - `{items}` is each item rendered as `"{name} {quantity} {shownUnit}"`, joined with ", ". Quantity has no trailing ".0".
  - `kcal` is `Int(meal.totals.kcal.rounded())`. When kcal is unknown, the chip is skipped.
- **Assembly:** dedupe by id, then drop the `hidden` ids. If no send chip is in the first two and one exists later, move the first send chip to index 1. Then take the first `limit` chips.

- [ ] **Step 1: Write the failing tests** in `QuickPromptsTests` (Swift Testing). Build a helper `input(...)` with defaults: `hour 12`, `today "2026-11-17"`, `yesterday "2026-11-16"`, empty meals, `kcalTarget 1600`, `limit 4`, `wide false`. Use a helper `meal(hour:items:kcal:revision:)` that builds a saved `MealReadModel` on a fixed calendar. Tests:
  - `morningWithYesterdaysBreakfastLeadsWithSameBreakfast`: hour 8, yesterday's 08:20 meal with oats 1 bowl at 320 kcal. `choose(...).map(\.id) == ["relog", "ask.yesterday", "log.slot", "log.weight"]`, `first?.title == "Same breakfast"`, `first?.kcal == 320`, and the action text is `"For breakfast I had oats 1 bowl"`.
  - `frequentMealIsUsedWhenYesterdayHasNone`: two older dinners with the same foods. The title is `"Usual dinner"` and the source is the newer one.
  - `afterAMealLogTheFollowUpsLeadWithTheQuestion`: `latest = .meal(id, 1, today)` with a matching meal at 13:10. The ids are `["ask.calories", "fix.portion", "add.drink"]` and the `fix.portion` fill is `"Make lunch a smaller portion: "`.
  - `followUpsNeedTodaysExchange`: the same latest with `localDate: yesterday` gives slot chips, not follow-ups.
  - `changedMealDropsItsFollowUps`: the meal revision is now 2 while the committed revision is 1, so there are no `fix.portion` chips.
  - `eveningShortOnProteinAsksForIdeas`: hour 20, protein 40 of 100. Contains `ask.protein` and not `ask.calories`.
  - `wideSwapsCaloriesForBalanced`, and `limit 2` gives a count of 2 that still includes a send chip.
  - `hiddenChipsAreSkippedBeforeTheLimit`: hiding `relog` at hour 8 gives `["ask.yesterday", "log.slot", "log.weight"]`.
  - `newUserWithoutTargetGetsLoggingChipsOnly`: hour 13, no target, no history gives `["log.slot", "log.weight"]`, with no send chip and no crash.
  - `loggedSlotOffersASnack`: hour 13 with lunch logged gives `["ask.calories", "log.snack", "log.weight"]`.
  - `weighInHidesWeightChipAndMorningCardToo`.
  - `everyTitleFitsEighteenCharacters`: run every rule path above and check every title has `count <= 18`.
  - `sendChipsAreTheApprovedQuestions`: every `.send` text is in `["How was yesterday?", "Calories left?", "Was it balanced?", "Protein ideas?", "Weekly trend?"]`.

- [ ] **Step 2: Run the tests and confirm they fail.** Use XcodeBuildMCP simulator test with `-only-testing:MivuTests/QuickPromptsTests`. Expected: the build fails because `QuickPrompts` is undefined.

- [ ] **Step 3: Implement `QuickPrompts.choose` and the types above** in `QuickPrompts.swift`, as one pure enum with no SwiftUI import.

- [ ] **Step 4: Run the tests and confirm they all pass.** Then commit:
```bash
git add ios/Mivu/Coach/QuickPrompts.swift ios/MivuTests/QuickPromptsTests.swift ios/Mivu/Localizable.xcstrings
git commit -m "feat(coach): choose context-aware quick prompts"
```

### Task 2: Bounded recent-meals query

**Files:**
- Create: `ios/Mivu/Diary/DiaryDatabaseRecentMeals.swift` (`extension DiaryDatabase`)
- Modify: `ios/Mivu/Diary/DiaryStore.swift` (add a pass-through next to `coachFindMeals`, around line 467)
- Test: `ios/MivuTests/RecentMealsTests.swift`

**Interfaces:**
- Consumes: `RecentMeal` (Task 1); `DiaryTransaction.mealProjection(id:)`, used by `dayProjection` in `DiaryDatabaseMealMutations.swift:223`.
- Produces: `DiaryStore.recentMeals(from: String, to: String, expectedProfileID: UUID) throws -> [RecentMeal]` and the matching `DiaryDatabase` method.

- [ ] **Step 1: Write the failing tests.** Follow the store setup used by `DiaryTests`.
  - `recentMealsAreSavedOnlyNewestFirstAndBounded`: seed 3 days (one with an unsaved meal) and query `from…to` covering 2 of them. Check that only saved meals in range are returned, ordered by `eatenAt` descending, each with its day's `localDate`.
  - `recentMealsRejectAnotherProfile`: the wrong `expectedProfileID` throws, like `coachFindMeals`.
- [ ] **Step 2: Run them and confirm they fail.** Use `-only-testing:MivuTests/RecentMealsTests`. Expected: the build fails because the method is missing.
- [ ] **Step 3: Implement.**
  - Wrap the query in `domainRead(expectedProfileID:)`.
  - Select meal ids joined to their day where the day's `localDate` is between `from` and `to` and the meal's `revision > 0`.
  - Order by `eatenAt DESC` with `LIMIT 60`.
  - Map each id through `mealProjection(id:)`.
  - Validate dates with `validLocalDate`, as `coachFindMeals` does.
- [ ] **Step 4: Run the tests and confirm they pass.** Then commit with `feat(diary): bounded recent-meals read for quick prompts`.

### Task 3: `copy_meal` Coach tool

**Files:**
- Modify: `ios/Mivu/Coach/CoachTools.swift`. Add the schema next to `log_food` (around line 110) and a parse case next to `case "log_food"` (line 225).
- Modify: `ios/Mivu/Coach/CoachUITestInference.swift`. Add a fixture branch for a quoted-meal re-log.
- Test: `ios/MivuTests/CoachEditParityTests.swift` (the parse tests live here) and `ios/MivuTests/CoachEngineTests.swift` (one end-to-end turn).

**Interfaces:**
- Consumes: `CoachTools.parse(_:meals:evidence:receipts:workouts:found:zone:)`, `CoachCommand.write(.food(date:items:eatenAt:reviewFirst:))`, and `CoachContext.Meal.items: [FoodItem]`.
- Produces: tool `copy_meal` with arguments `source_meal_id: string`, `expected_revision: integer`, `target_local_date: string`, and `eaten_at: string|null`. `eaten_at` uses the same `unconfirmedTime` schema and rules as `log_food`. All are required except `eaten_at`.

**Tool description (exact copy):** "Log again, unchanged, a saved meal the user quoted to repeat when their message keeps the same foods and amounts. Call get_meal on it first. Copies its items and nutrition exactly as a new meal on target_local_date. If they changed foods or amounts, or get_meal fails, use log_food instead."

- [ ] **Step 1: Write the failing tests.**
  - `copyMealCopiesItemsWithNewIDs`: parse `copy_meal` for a known meal at its revision. Expect `.write(.food)` with the same names, quantities, units and nutrition, and with item ids that all differ from the source's.
  - `copyMealRefusesAStaleRevision`: revision − 1 throws `CoachError.invalidArguments`.
  - `copyMealRefusesAnUnknownMeal`: an id not in `meals` throws.
  - `copyMealKeepsEatenAtRules`: an `eaten_at` on another calendar day is dropped, as with `log_food`.
  - In `CoachEngineTests`: `quotedRelogLogsTheSameKcal`. A turn with `reply: .meal(source)` and fixture calls `get_meal` then `copy_meal` gives a receipt for a new meal whose kcal total equals the source's.
- [ ] **Step 2: Run them and confirm they fail** (unknown tool).
- [ ] **Step 3: Implement.**
  - Add the schema.
  - Add the parse case: look up the meal in `meals` by id with `revision == expected_revision`, give each item a fresh `id`, run `validateItems`, and resolve `eaten_at` exactly as `log_food` does. Return `.write(.food(date:items:eatenAt:reviewFirst: false))`.
  - In `CoachUITestInference.respond`, when `context.replyTo?.target` is `.meal(id)` and the text has the prefix `"For "` and contains `" I had "`:
    - with no outputs yet, call `get_meal(id)`;
    - after the get_meal output, call `copy_meal` with its revision and the capture date;
    - after that, reply `"Logged it again."`.
- [ ] **Step 4: Run** `-only-testing:MivuTests/CoachEditParityTests` and `-only-testing:MivuTests/CoachEngineTests`, and confirm they pass. Then commit with `feat(coach): copy a quoted meal exactly`.

### Task 4: Short Pip lines beside the chips

**Files:**
- Modify: `ios/Mivu/Coach/PipLine.swift` (`PipLine.current`)
- Test: `ios/MivuTests/PipLineTests.swift`

**Interfaces:**
- Produces: `PipLine.current(..., chips: Bool = false)`, as a new trailing parameter. When `chips` is true and the line would be an idle `.say`, it returns the short line:
  - `mealsLogged` → "Anything else?";
  - 4..<11 → "Morning!";
  - 11..<15 → "Lunch time?";
  - 15..<18 → "Snack time?";
  - 18..<22 → "Dinner time?";
  - otherwise → "Hi again!".
  Status, working, problem and connect lines are unchanged.

- [ ] **Step 1: Write the failing test** `chipsShortenOnlyTheIdleLine`. Use `line(hour: 8, chips: true) == .say("Morning!")`, and check that `processing: true, chips: true` still gives `.working("Counting that up…")`. Extend the private `line(...)` helper with `chips: Bool = false`.
- [ ] **Step 2: Run** `-only-testing:MivuTests/PipLineTests` and confirm it fails.
- [ ] **Step 3: Implement the parameter.**
- [ ] **Step 4: Run the test and confirm it passes.** Then commit with `feat(coach): keep Pip's line short beside quick prompts`.

### Task 5: The chip row in the composer, settings switch and hiding

**Files:**
- Modify: `ios/Mivu/Coach/CoachView.swift`. This replaces `showsStarters`/`starters` (lines 559–579 and their uses at 479 and 523), wraps `companionStrip`'s sibling input row (lines 483–492) in the tray, and changes the `companionStrip` Pip size (line 367) and the `pipLine` call (line 395).
- Modify: `ios/Mivu/Coach/CoachViewModel.swift`. Add a `recentMeals` state and its refresh.
- Modify: `ios/Mivu/Diary/SettingsView.swift`. Add the switch in `companionSection` (line 121).
- Test: `ios/MivuUITests/CoachUITests.swift`. Replace the `coachStarter` assertions near line 517. Duo cases go in `ios/MivuUITests/DuoLayoutUITests.swift`.

**Interfaces:**
- Consumes: Task 1 `QuickPrompts.choose`, `QuickPromptInput` and `QuickPrompt`; Task 2 `DiaryStore.recentMeals`; Task 4 `PipLine.current(..., chips:)`.
- Produces:
  - `CoachViewModel.recentMeals: [RecentMeal]` (private(set)) and `func refreshRecentMeals() async`. It queries `from = today − 14 days` and `to = yesterday` for the active profile.
  - `@AppStorage("coachSuggestionsEnabled") var suggestionsEnabled = true`.
  - `@AppStorage("coachHiddenSuggestions") var hiddenSuggestions = ""`, holding comma-joined chip ids.
  - Accessibility identifiers: `coachQuickPrompt-<id>` on each chip, `coachQuickPrompts` on the row, and `coachSuggestionsToggle` on the switch.

**Behaviour to implement:**
- **Visibility:** `showsQuickPrompts` is true when all of these hold:
  - `suggestionsEnabled`;
  - the draft text is empty and there are no attachments;
  - `voice.phase == .idle` and `!coach.isSending`;
  - the latest exchange has no open clarification (no `question` with candidates or options while `window.isLatest`);
  - the chip list is not empty.

  Unlike the old starters, the row shows while `editing` too.
- **Input:** build `QuickPromptInput` from:
  - `coach.diary.readModel`: meals, totals, `activeGoal?.targets`, `weight != nil`, and the active day's local date;
  - `recentMeals`;
  - the morning-card condition already in `composer`;
  - the latest exchange's last receipt with a `mealID`, `weightID` or `workoutID`, mapped to `QuickPromptLatest` with `displayLocalDate`;
  - `limit`: 2 when `isWide`, when the measured window height is under 700 pt (measure with `onGeometryChange` on a background that ignores the safe area, as `DuoLayoutRoot` does), or when `typeSize >= .accessibility3`; otherwise 4;
  - `wide: isWide`;
  - the hidden set.
- **Tray:** wrap the chip row and the existing input `HStack` in one `VStack(spacing: 8)` with `.padding(8)` and `.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))`, plus a 0.5 pt `diaryRule` hairline. Pip still stands on its top edge.
- **Chips:**
  - Use `ScrollView(.horizontal)` with an `HStack(spacing: 8)`, `.scrollTargetBehavior(.viewAligned)`, and a trailing 24 pt fade mask only when the content overflows.
  - Each chip is a `Button` at 36 pt height with `.frame(minHeight: 44)` and `.contentShape`. The text is `.subheadline` medium. The fill is `diarySurface`, with a `diaryRule` hairline stroke on plain chips.
  - **Send chips** have a trailing 20 pt `diaryAccent` circle holding a white `arrow.up` at 11 pt bold.
  - **The re-log chip:**
    - 3 pt leading inset and a 30 pt circle thumbnail;
    - the thumbnail is `DiaryPhotoPreview(model: coach.diary, reference: photo, height: 30)` clipped to a circle, or `fork.knife` at 15 pt on a `diaryAccent.opacity(0.12)` disc;
    - an 8 pt gap, then the title, then the kcal at 13 pt `diarySecondary`, `.monospacedDigit()`;
    - the fill is `diaryAccent.opacity(0.09)` over `diarySurface` (0.22 in dark), with no border.
- **Tap:**
  - `.fill(text)`: set `coach.attachmentDraft.text = text` and `editing = true`, with `.sensoryFeedback(.selection)`.
  - `.send(text)`: set the draft text and call `await coach.send()`, with `.sensoryFeedback(.impact(weight: .light))`.
  - `.relog`: set the text, then `coach.attachmentDraft.reply = CoachReply(target: .meal(mealID: id), excerpt: excerpt)`, then `editing = true`.
- **Motion:**
  - On insert, chips use `.transition(.opacity.combined(with: .offset(y: 6)))` with `.animation(.snappy(duration: 0.22).delay(Double(index) * 0.03))`.
  - On removal, use `.easeOut(duration: 0.12)`.
  - Under `reduceMotion`, use `.opacity` with `.easeOut(duration: 0.15)`.
- **Hiding:** add `.contextMenu { Button("Hide this suggestion", systemImage: "eye.slash") { hide(prompt.id) } }`.
- **Settings:** in `companionSection`, add `Toggle("Show suggestions", isOn: $suggestionsEnabled)` with identifier `coachSuggestionsToggle` and the footer "Quick prompts above the Coach message box." When it switches from off to on, clear `hiddenSuggestions`.
- **Refresh:** call `refreshRecentMeals()` in `.task`, on `scenePhase == .active`, and on `onChange(of: coach.diary.readModel?.head)`. Recompute the hour with a `TimelineView(.everyMinute)` around the row, or an equivalent hourly tick.
- **Pip:** pass `chips: showsQuickPrompts` to `PipLine.current`. The `CompanionView` size is 64 when the window is short, otherwise `typeSize.isAccessibilitySize ? 76 : 112`.
- **VoiceOver:**
  - A fill chip reads `accessibilityLabel(title)` with `accessibilityHint("Fills the message")`.
  - A send chip uses the hint "Sends to Coach".
  - The re-log label is "{title}, {kcal} calories".

- [ ] **Step 1: Write the failing UI tests** in `CoachUITests`, using the existing `--coach-ui-test --coach-inference-fixture` launch:
  - `quickPromptFillDoesNotSend`: tap `coachQuickPrompt-log.slot`. Expect `coachInput.value` to start with "For " and no new exchange to appear.
  - `quickPromptSendSends`: tap `coachQuickPrompt-ask.calories` (with the fixture's kcal target). Expect an exchange with text "Calories left?" to appear.
  - `quickPromptsHideWhileTypingAndReturn`: type "a" and expect `coachQuickPrompts` not to exist. Clear the field and expect it to exist.
  - `quickPromptsStepAsideForAClarification`: send the existing `clarify-options` fixture message, and expect `coachQuickPrompts` not to exist while `coachOptionChip` exists.
  - `hiddenSuggestionStaysHidden`: long-press a chip, then tap "Hide this suggestion". Expect that chip id to be gone after relaunch.
  - `suggestionsSwitchTurnsTheRowOff`: open settings, toggle `coachSuggestionsToggle` off, return to Coach, and expect `coachQuickPrompts` not to exist.
  - `relogChipCopiesYesterdaysMeal`: launch with yesterday's meal seeded through the existing yesterday path of the inference fixture ("…yesterday…" message). Tap `coachQuickPrompt-relog`, then send. Expect the new saved-meal kcal to equal the chip's kcal.
  - Replace the `coachStarter` assertion near line 517 with `coachQuickPrompts`.
  - In `DuoLayoutUITests`: `quickPromptsShowTwoChipsSideways` (`--wide-layout-ui-test`) asserts at most 2 `coachQuickPrompt-` buttons and no `coachQuickPrompt-ask.calories`.
- [ ] **Step 2: Run the new tests on an iPhone 17 simulator** and confirm they fail. Use `-only-testing:MivuUITests/CoachUITests/<name>` for each.
- [ ] **Step 3: Implement** the behaviour above in `CoachView`, `CoachViewModel` and `SettingsView`. Delete `showsStarters` and `starters`. Add every new string to `Localizable.xcstrings`.
- [ ] **Step 4: Run the new UI tests and confirm they pass.** Then run the existing `CoachClarificationUITests` and confirm they still pass. Then commit with `feat(coach): context-aware quick prompts in the composer`.

### Task 6: Remove "See today" and "See progress"

**Files:**
- Modify: `ios/Mivu/Coach/CoachReplyLines.swift:36-55` (`FollowUp`, `followUps`)
- Modify: `ios/Mivu/Coach/CoachView.swift:706-728` and `:866-880` (`open`, `title`, `identifier`, and the follow-up row with its `isWide && .today` filter)
- Modify: `ios/Mivu/Coach/CoachPane.swift` / `CoachSidePane.swift`. Remove the `.progress` pane case only if no other code opens it (check with `rg "\.progress" ios/Mivu/Coach`).
- Test: `ios/MivuTests/CoachReplyLinesTests.swift`, `ios/MivuUITests/CoachUITests.swift:172`, and `ios/MivuUITests/DuoLayoutUITests.swift:91,136`.

**Interfaces:**
- Produces: `CoachReplyLines.FollowUp` with the single case `.day(String)`, and `followUps(for:consulted:today:)`, which returns only past-day follow-ups. A consulted `.day(today)` and `.progress` produce nothing.

- [ ] **Step 1: Update the tests first.**
  - In `CoachReplyLinesTests`, a meal receipt yields `[]`, a weight receipt yields `[]`, and a consulted past date yields `[.day(date)]`.
  - Delete the UI assertions on `coachFollowUp-today` and `coachFollowUp-progress`. Replace the Duo progress-pane test at line 136 with an assertion that `coachFollowUp-progress` does not exist.
- [ ] **Step 2: Run** `-only-testing:MivuTests/CoachReplyLinesTests` and confirm it fails.
- [ ] **Step 3: Remove the cases and their view code.** Delete the strings "See today" and "See progress" from `Localizable.xcstrings`.
- [ ] **Step 4: Run** `CoachReplyLinesTests` and the edited UI tests, and confirm they pass. Then commit with `refactor(coach): drop See today and See progress follow-ups`.

### Task 7: Verification, UX review and PR

**Files:**
- Create: `docs/verification/2026-11-17-coach-quick-prompts.md`, plus screenshots in `docs/verification/coach-quick-prompts/`.

- [ ] **Step 1: Rebase onto `origin/main`** once #145 has merged, then re-run Tasks 1–6's focused suites. Record the SHA, simulator and result counts.
- [ ] **Step 2: Capture screenshots** in light, dark and AX3 text:
  - on an iPhone 17 at 8:10, after a lunch log, and at 20:30 with the keyboard up;
  - on the iPhone Duo, using `device_open` and `agent-device fold closed|open`, in closed (keyboard down and up) and open-sideways poses.
- [ ] **Step 3: Send the screenshots and the spec to an independent UX/UI reviewer** (AI-tool UX specialist). Fix the blocking findings, then recapture.
- [ ] **Step 4: Run Ponytail Review on the branch diff** and fix the blocking findings.
- [ ] **Step 5: Write the verification record** with the SHA, environment, named tests with pass counts, screenshot paths, and the UX review outcome. Report any blocked gate honestly.
- [ ] **Step 6: Push, open the PR,** and verify the required Linux checks.
  - Title: `feat(coach): context-aware quick prompts`.
  - The body summarises the behaviour and links the spec and verification record. Do not mention AI tools.
