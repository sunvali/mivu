# Pip Entry Points Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every Today/Diary/Progress button either opens Coach (quoting the record it is about) or says "manually".

**Architecture:** Reuse the existing Diary→Coach handoff (`OpenDiaryCoachAction(target, draft:, reply:)` → `CoachNavigationRequest` → `CoachView` navigation task → `CoachViewModel.startReply`). Add two `CoachReply.Target` kinds for weights and workouts, resolved in `coachReplyContext`. Sample mode keeps `MealComposerView`.

**Tech Stack:** SwiftUI, Swift Testing (`MivuTests`), XCUITest (`MivuUITests`), XcodeBuildMCP.

**Spec:** `docs/superpowers/specs/2026-10-21-pip-entry-points-design.md`

## Global Constraints

- English only; Dynamic Type, VoiceOver labels, 44-pt minimum targets, reduced motion respected.
- No handoff opens the keyboard; the person taps the field.
- A handoff never replaces a message the person already started (`startReply` rule stays).
- `CoachReply` is persisted: older stored payloads must still decode.
- Sample mode (`model.sampleMode`): primary log and "Add note or photo" keep opening `MealComposerView`.
- Every non-swipe action also has a visible button or context menu and a VoiceOver action (swipe is never the only path).
- Tests first; run focused tests with XcodeBuildMCP; record the tested SHA.

## Review Focus

1. Unrecorded Diary day: Ask Pip prefills "For <date>: " and does not crash or quote a missing day — covered by Task 4 UI test.
2. Composer already holds text when a handoff arrives: the draft is kept, no quote, keyboard stays down — covered by existing `navigationReplyNeverReplacesInProgressDraft` plus Task 2 assertion.
3. Quoted weight/workout deleted before send: context marks `unavailable` — Task 1 parameterized test.
4. Old archive/turn payloads with only message/meal/item/day targets still decode — Task 1 decode test.
5. Sample mode still logs via the composer — Task 3 keeps `logMeal` composer path in sample-mode UI tests.

## Design note (builder call, from the code)

On a Diary day the bottom bar already shows "Log meal" next to "Ask Pip". After this change both would open Coach quoting the day, so the Diary day bar becomes **Ask Pip** + **Add manually** (no separate Log with Pip there). Today keeps **Log with Pip** + **Add manually**.

---

### Task 1: Weight and workout reply targets

**Files:**
- Modify: `ios/Mivu/Coach/CoachModels.swift` (`CoachReply.Target`, `CoachContext.Reply`)
- Modify: `ios/Mivu/Diary/DiaryDatabaseCoachContext.swift` (`coachReplyContext`)
- Modify: `ios/Mivu/Coach/CoachReplyQuote.swift` (`author`, `composerTitle`)
- Modify: `ios/Mivu/Coach/CoachView.swift` (`openQuote`)
- Test: `ios/MivuTests/CoachReplyTests.swift`

**Interfaces:**
- Produces: `CoachReply.Target.weight(weightID: UUID)`, `.workout(workoutID: UUID)`; `CoachContext.Reply.weight: WeightEntry?`, `.workout: WorkoutSession?`.

- [ ] **Step 1: Write failing tests** in `CoachReplyTests`:
  - `inferenceContextCarriesQuotedWeight` / `inferenceContextCarriesQuotedWorkout`: seed a fixture with one weight and one workout (synthetic values), quote each, `#expect(context.replyTo?.weight?.id == weight.id)` / `.workout?.id == workout.id`, `unavailable == nil`.
  - Extend `unavailableReplyTargetIsExplicit` arguments with `.weight(weightID: UUID())`, `.workout(workoutID: UUID())`; also `#expect(context.replyTo?.weight == nil && context.replyTo?.workout == nil)`.
  - `legacyReplyTargetsStillDecode`: before adding cases, print `JSONEncoder` output for a `CoachReply` with `.day(dayID:)` and `.meal(mealID:)` targets; paste those literal strings into the test and `#expect` they decode to the same values.
- [ ] **Step 2: Run** `CoachReplyTests` via XcodeBuildMCP `test_sim` with `-only-testing:MivuTests/CoachReplyTests`. Expected: compile failure on the new cases.
- [ ] **Step 3: Implement.** Add the two cases. In `coachReplyContext`, `case .weight(let id)`: `value.weight = try transaction.weight(id: id)`; `case .workout(let id)`: same with `workout(id:)`, then drop it (ids only) if `JSONEncoder().encode` > 8192 bytes, mirroring the meal branch. `author`/`composerTitle`: both new cases return `"Progress"` / `"From Progress"`. `openQuote`: new cases `return` (quote not tappable; `shortcut:` comment — seek the record's day when Progress gets a record route).
- [ ] **Step 4: Run** the same tests. Expected: PASS.
- [ ] **Step 5: Commit** `feat(coach): quote weights and workouts in a reply`.

### Task 2: Handoffs leave the keyboard down

**Files:**
- Modify: `ios/Mivu/Coach/CoachView.swift:142` (drop `{ editing = true }` after `startReply`; keep the call)
- Test: `ios/MivuUITests/CoachReplyUITests.swift` (or the Diary handoff test in `DiaryAmountEditorUITests.swift` that asserts the quote)

- [ ] **Step 1: Write failing assertion** in the existing Diary→Coach quote UI test: after the handoff, `#expect`-equivalent `XCTAssertFalse(app.keyboards.firstMatch.exists)` while `coachReplyCancel` exists.
- [ ] **Step 2: Run** that single UI test. Expected: FAIL (keyboard shown).
- [ ] **Step 3: Implement** the one-line change. In-chat swipe reply (`reply(to:fromPip:)`, line ~518) keeps focusing — it is not a handoff.
- [ ] **Step 4: Run** the test. Expected: PASS.
- [ ] **Step 5: Commit** `fix(coach): Diary handoffs leave the keyboard down`.

### Task 3: Log with Pip + Add manually

**Files:**
- Modify: `ios/Mivu/Diary/DiaryStyle.swift` (`DiaryCaptureAction`)
- Modify: `ios/Mivu/Diary/TodayView.swift` (Today list `safeAreaInset`, ~line 680; sheets ~692)
- Modify: `ios/Mivu/Diary/HistoryView.swift` (bottom bar ~95, `askPipAction` ~166)
- Test: `ios/MivuUITests/DiaryUITests.swift` (new test), existing sample-mode tests unchanged

**Interfaces:**
- Produces: `DiaryCaptureAction(title: LocalizedStringKey = "Log with Pip", systemImage: String = "sparkles", identifier: String = "logMeal", action:)` and `DiaryManualAction(identifier: String, action:)` — secondary bordered/glass button labelled "Add manually", `systemImage: "number"`, min height 52.

- [ ] **Step 1: Write failing UI test** `testLogWithPipOpensCoachAndAddManuallyOpensForm` (non-sample, Coach UI-test fixture): tap `logMeal` → Coach tab selected, keyboard absent; back to Today, tap `addManually` → manual nutrition sheet title "Enter nutrition".
- [ ] **Step 2: Run** it. Expected: FAIL.
- [ ] **Step 3: Implement.**
  - Today: `HStack { DiaryCaptureAction { sampleMode ? showComposer = true : openChat(nil, expectedSelection:) }; DiaryManualAction(identifier: "addManually") { showManualNutrition = true } }`. Sample mode label stays "Log meal" with `plus.circle.fill`. Manual sheet: `ManualNutritionView` for the active day, as HistoryView does.
  - Diary day bar: sample mode keeps today's `logMealForDay` composer button; otherwise Ask Pip (Task 4) + `DiaryManualAction(identifier: "addManuallyForDay")` shown only when `recordedDay` exists (the form needs a day).
- [ ] **Step 4: Run** the new test plus existing sample-mode tests that tap `logMeal` (`DiaryUITests`, `CompanionUITests`). Expected: PASS; any non-sample test that used `logMeal` to create a meal switches to sample mode or the Coach fixture.
- [ ] **Step 5: Commit** `feat(today): log with Pip and add manually`.

### Task 4: Ask Pip quotes every record

**Files:**
- Modify: `ios/Mivu/Diary/HistoryView.swift` (`askPipAction`)
- Modify: `ios/Mivu/Progress/ProgressView.swift` (weight rows ~390, workout rows ~427)
- Test: `ios/MivuUITests/CoachReplyUITests.swift`, `ios/MivuUITests/ProgressUITests.swift`

- [ ] **Step 1: Write failing UI tests**:
  - `testDiaryDayAskPipQuotesDay`: open a recorded day, tap Ask Pip → `coachReplyCancel` exists and quote text contains the day excerpt.
  - `testUnrecordedDayAskPipPrefillsDate`: empty date → composer text begins "For ".
  - `testWeightAndWorkoutAskPipQuoteRecord` in `ProgressUITests`: context-menu "Ask Pip" on a weight row and on a workout row → quote shown.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement.**
  - `askPipAction`: recorded day → `openChat(.day(day.id), reply: CoachReply(target: .day(dayID: day.id), excerpt: DiaryWeek.format(day.localDate, "EEEE, d MMM")), …)`; unrecorded unchanged.
  - Progress rows: `.contextMenu { Button("Ask Pip", systemImage: "sparkles") { … } }`, `.swipeActions(edge: .leading) { same.tint(.diaryAccent) }`, `.accessibilityAction(named: "Ask Pip") { … }`. Excerpts: weight `"Weight · \(value formatted) \(unit) · \(EEE d MMM)"`, workout `"\(kind title) · \(durationMinutes) min · \(EEE d MMM)"`. Target `.day(dayID)` seek when the record has a day, else nil. Identifier `askPipWeight` / `askPipWorkout`.
- [ ] **Step 4: Run** them. Expected: PASS.
- [ ] **Step 5: Commit** `feat(diary): Ask Pip quotes days, weights and workouts`.

### Task 5: Meal actions via Coach; manual labels

**Files:**
- Modify: `ios/Mivu/Diary/MealDetailView.swift` (remove `halfPortion` ~88; `correctMeal` row ~81 and ⋯ menu ~138)
- Modify: `ios/Mivu/Diary/TodayView.swift` (`quickLogAddNote` ~419, `noteMealID` sheet ~324)
- Modify: `ios/Mivu/Progress/ProgressView.swift:404,418`, `ios/Mivu/Progress/ProgressEditorViews.swift:586,728`, `ios/Mivu/Diary/HistoryView.swift:124-125`
- Test: `ios/MivuUITests/DiaryUITests.swift`, `ios/MivuUITests/ProgressUITests.swift` (identifier/label updates)

- [ ] **Step 1: Write failing UI test** `testAddNoteOrPhotoQuotesMealInCoach` (non-sample): meal detail → `correctMeal` → Coach shows `coachReplyCancel`, keyboard absent; `halfPortion` does not exist.
- [ ] **Step 2: Run** it. Expected: FAIL.
- [ ] **Step 3: Implement.**
  - Non-sample `correctMeal` and the menu item call the existing `askPip(about: nil, in: meal)`; sample mode keeps `showCorrection = true`.
  - Quick-log "Add Note": non-sample → `openCoachAction(nil, reply: CoachReply(target: .meal(mealID: id), excerpt: "Meal"), …)` using the meal title when loaded; sample keeps the `noteMealID` sheet.
  - Delete the "I ate half" button.
  - Labels: "Log morning weight" / "Morning weight" → "Add weight manually"; "Log workout" → "Add workout manually"; editor nav titles for new entries follow ("Add weight manually", "Add workout manually"); keep identifiers.
- [ ] **Step 4: Run** the new test and the label-touching tests in `ProgressUITests`/`DiaryUITests`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(diary): meal notes go through Coach and manual forms say so`.

### Task 6: Verification and PR

- [ ] Run focused `MivuTests` (`CoachReplyTests`) and the UI tests touched above with XcodeBuildMCP; record SHA, result bundle and counts in `docs/verification/2026-10-21-pip-entry-points.md`.
- [ ] Ponytail Review of the branch; fix blocking findings.
- [ ] Open PR `feat(diary): one way to log with Pip and quoted Ask Pip everywhere`; verify hosted title/script checks.
