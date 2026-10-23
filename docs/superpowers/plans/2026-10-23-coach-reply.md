# Coach Reply Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Coach shows Pip's short, checked prose plus Today-styled receipt cards instead of raw fact dumps.

**Architecture:** A pure `CoachReplyCheck` decides whether the model's final prose is grounded. `CoachEngine` keeps the prose when it passes. Otherwise it falls back to a one-line template from receipts, or to a one-line fact line for read-only turns. `CoachReceiptView` is restyled with the Today visual language. A weight chip and follow-up chips are added. Nothing new is stored except optional weight and workout fields decoded from existing receipt JSON.

**Tech Stack:** Swift, SwiftUI, Swift Testing (`@Suite`/`@Test`/`#expect`), XCUITest, XcodeBuildMCP.

**Spec:** `docs/superpowers/specs/2026-10-23-coach-reply-design.md`

## Global Constraints

- The UI is English only. Keep Dynamic Type, VoiceOver, Reduce Motion and minimum 44-point touch targets.
- Use only synthetic inputs in tests.
- Keep `CoachReplyCheck` and `CoachReplyLines` free of store and UI dependencies so a later server worker can reuse them.
- Receipts are immutable. Cards render `CoachCommittedReceipt`, never the current record, except for the existing change and availability notices.
- Use inline Markdown only: `AttributedString(markdown:options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))`, with a plain-text fallback.
- Use Conventional Commit titles. Never mention codex, AI or assistants in commits.
- Run the focused tests with XcodeBuildMCP (`ios/Mivu.xcodeproj`, scheme `Mivu`, iPhone simulator). Record the source SHA.

## Review Focus

- A reply containing a percentage or a range ("about 30%", "450–460 kcal") passes only if every number is grounded. Test it in Task 1.
- A reply that mentions the user's own typed number ("73.6 kg"): the typed number appears in the turn's tool output and receipts, so it passes. Test it in Task 1 (the allowed set includes receipt weight values).
- A multi-receipt turn (meal plus weight) uses receipt order for its template line and shows both cards. Test it in Task 2.
- A legacy receipt whose `resultJSON` does not decode shows "Saved." / "Weight saved." / "Workout saved." without crashing. Test it in Task 2.
- At accessibility text sizes, the meal card's dish rows stack and stay readable, with no truncated kcal. Check this in the Task 6 UI step.

---

### Task 1: `CoachReplyCheck`

**Files:**
- Create: `ios/Mivu/Coach/CoachReplyCheck.swift`
- Test: `ios/MivuTests/CoachReplyCheckTests.swift`

**Interfaces:**
- Produces:
  - `enum CoachReplyCheck`
  - `static func allowedNumbers(in sources: [String], receipts: [CoachCommittedReceipt]) -> Set<Decimal>`: every number token in the sources, every item quantity and nutrient value, and the summed kcal, carbs, protein and fat for each receipt. Each value is added along with its roundings to the nearest 1 and the nearest 10. Weight value and workout minutes come from Task 2's fields; until Task 2 lands, read them if present.
  - `static func numbers(in text: String) -> [Decimal]`: parses `1,240`, `73.6`, `-0.4` and the parts of `2026-10-23` and `8:12`.
  - `static func passes(_ prose: String, allowed: Set<Decimal>, receipts: [CoachCommittedReceipt]) -> Bool`: implements spec rules 1, 3 and 4. Rule 2 stays in the engine.

- [ ] **Step 1: Write the failing tests**

```swift
@Suite struct CoachReplyCheckTests {
    @Test func groundedProsePassesWithGroupingAndRounding() {
        let allowed = CoachReplyCheck.allowedNumbers(in: ["{\"kcal\":1240,\"remaining\":458}"], receipts: [])
        #expect(CoachReplyCheck.passes("About **1,240** kcal, roughly 460 left.", allowed: allowed, receipts: []))
    }
    @Test func inventedNumberFails() {
        let allowed = CoachReplyCheck.allowedNumbers(in: ["{\"kcal\":420}"], receipts: [])
        #expect(!CoachReplyCheck.passes("You have 9999 kcal left.", allowed: allowed, receipts: []))
    }
    @Test func percentAndRangeNeedEveryNumberGrounded() {
        let allowed = CoachReplyCheck.allowedNumbers(in: ["{\"a\":450,\"b\":460}"], receipts: [])
        #expect(CoachReplyCheck.passes("Between 450–460 kcal.", allowed: allowed, receipts: []))
        #expect(!CoachReplyCheck.passes("About 30% of target.", allowed: allowed, receipts: []))
    }
    @Test func receiptSumsAndWeightAreAllowed() { /* meal receipt with items 320+240 kcal → "560" passes; weight receipt 73.6 kg → "73.6 kg" passes */ }
    @Test func awaitingReviewForbidsLoggedOrSaved() { /* receipt.submissionState = .awaitingReview → "Your lunch is saved." fails, "Ready for review." passes */ }
    @Test func emptyProseFails() { #expect(!CoachReplyCheck.passes("  \n", allowed: [], receipts: [])) }
}
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run with XcodeBuildMCP: the `MivuTests/CoachReplyCheckTests` test.
Expected: the build fails because `CoachReplyCheck` is not defined.

- [ ] **Step 3: Implement `CoachReplyCheck` in `ios/Mivu/Coach/CoachReplyCheck.swift`**

Tokenise with a regex such as `-?\d{1,3}(,\d{3})+(\.\d+)?|-?\d+(\.\d+)?`. Strip the commas and convert to `Decimal`. Treat dates and times as their component numbers, so they pass when their parts appear in the sources.

- [ ] **Step 4: Run the tests and confirm they pass**

Expected: all 6 pass.

- [ ] **Step 5: Commit**

`git commit -m "feat(coach): check reply numbers against turn facts"`

---

### Task 2: Committed weight and workout facts, plus the template line

**Files:**
- Modify: `ios/Mivu/Coach/CoachTimelineModels.swift:25-39` (`CoachCommittedReceipt`)
- Modify: `ios/Mivu/Diary/DiaryDatabaseQueries.swift:289-330` (`ReceiptFacts`, `coachCommittedReceipt`)
- Modify: `ios/Mivu/Diary/DiaryDatabaseQueries.swift:376-440` (`coachReceiptSummary`)
- Test: `ios/MivuTests/CoachStoreTests.swift`, `ios/MivuTests/CoachReceiptPresentationTests.swift`

**Interfaces:**
- Produces: the optional fields `CoachCommittedReceipt.weightValue: Double?`, `weightUnit: String?`, `workoutKind: String?` and `workoutMinutes: Int?`, plus the new template sentences from `coachReceiptSummary`.

- [ ] **Step 1: Write the failing tests**
  - `weightReceiptCarriesCommittedValue`: log a synthetic 70 kg weight through the engine → `receipt.weightValue == 70`, `weightUnit == "kg"`. After the weight is corrected to 71, the receipt still says 70.
  - `workoutReceiptCarriesKindAndMinutes`: same idea, 30 minutes.
  - `templateLinesFollowReceiptOrder`: one turn with meal (560 kcal) and weight receipts → `coachCommittedSummary` is `"Saved — about **560** kcal. Everything is in the cards below."`.
  - `awaitingReviewTemplate`: → `"Your estimate is ready for review."`.
  - `legacyReceiptFallsBackWithoutFacts`: `resultJSON` set to `"{}"` → `"Weight saved."` / `"Workout saved."` / `"Saved."`.

- [ ] **Step 2: Run the tests and confirm they fail**

- [ ] **Step 3: Implement**
  - Add `value`, `unit`, `kind` and `durationMinutes` to `ReceiptFacts`. Populate the new fields only when `facts.id == receipt.weightID` or `facts.id == receipt.workoutID`.
  - Use the spec's exact wording for the template lines:
    - `"Saved — about **{kcal rounded to 10}** kcal."`
    - `"Saved."`
    - `"Your estimate is ready for review."`
    - `"Weight saved: **{value} {unit}**."`
    - `"Workout saved: {kind}, {minutes} minutes."`
    - `"Your goals are updated."`
    - `"Your preferences are updated."`
  - Return the first receipt's line, plus `" Everything is in the cards below."` when more than one meal, workout or weight card is shown.
  - Keep the existing special-case sentences unchanged.

- [ ] **Step 4: Run the tests and confirm they pass**

- [ ] **Step 5: Commit**

`git commit -m "feat(coach): short receipt lines with committed weight and workout facts"`

---

### Task 3: Read-only fact line

**Files:**
- Create: `ios/Mivu/Coach/CoachReplyLines.swift`
- Test: `ios/MivuTests/CoachReplyLinesTests.swift`

**Interfaces:**
- Consumes: `CoachProgress` (from `store.coachProgress`), `GoalRecord`, `WorkoutSession`
- Produces: `enum CoachReplyLines` with `static func factLine(progress: [CoachProgress], goals: [GoalRecord?], workouts: [WorkoutSession], preferencesRead: Bool) -> String`. It returns at most two sentences, in that order of priority.

- [ ] **Step 1: Write the failing tests**, using the spec's exact copy:
  - Single day with food 1142, target 1600 and remaining 458 → `"Today: 1142 of 1600 kcal, about 460 left."`. Use the app's number formatting; assert with whatever `formatted()` produces for en_US, which is `"1,142"`.
  - A day with no food → `"There's no food recorded for 2026-10-23 yet."`
  - Seven days with an average of 1850 over 5 known days → `"Last 7 days: about 1,850 kcal a day on 5 tracked days."`
  - Goal 1600 with protein 120 → `"Goal: 1,600 kcal a day, 120 g protein."`
  - Preferences only → `"Your preferences are up to date."`
  - Nothing read → `"I couldn't find anything to add there."`
  - A known 7-day weight average is appended as `"Weight average 73.6 kg."` while the two-sentence cap still holds.

- [ ] **Step 2: Run the tests and confirm they fail**
- [ ] **Step 3: Implement `factLine`.** Drop any part whose value is unknown.
- [ ] **Step 4: Run the tests and confirm they pass**
- [ ] **Step 5: Commit**

`git commit -m "feat(coach): one-line fact fallback for read-only turns"`

---

### Task 4: Engine keeps checked prose

**Files:**
- Modify: `ios/Mivu/Coach/CoachEngine.swift:24-80` (developer message, loop, final branch)
- Modify: `ios/Mivu/Coach/CoachUITestInference.swift:33,81` (fixture final text)
- Modify: `ios/Mivu/Diary/DiaryStore.swift:545-660` (remove the user-facing summary functions once they are unused)
- Test: `ios/MivuTests/CoachEngineTests.swift`, plus a rewrite of the reply-text assertions in the 19 test files that read `assistantText`

**Interfaces:**
- Consumes: from Task 1, `CoachReplyCheck.allowedNumbers` and `CoachReplyCheck.passes`. From Task 2, `store.coachCommittedSummary`. From Task 3, `CoachReplyLines.factLine`.

- [ ] **Step 1: Write the failing tests** in `CoachEngineTests`:
  - `progressQuestionKeepsGroundedProse`: a stub that calls `get_progress` and then returns `"You're at **1,142** kcal, about 460 left."` → `assistantText` equals that prose and does not contain `"Remaining from recorded food"`.
  - `inventedNumberFallsBackToFactLine`: a stub that returns `"9999 kcal left"` → `assistantText` is the Task 3 fact line and does not contain `"9999"`.
  - `mealTurnKeepsGroundedProse`: a multi-dish photo `log_food` with 7 items, then the prose `"That's a feast! Saved as dinner, about **1,240** kcal."` → one exchange, one meal receipt with 7 items, and the prose is stored.
  - `awaitingReviewProseFallsBack`: a review-first meal plus the prose `"Logged your lunch."` → `"Your estimate is ready for review."`
  - `unsupportedSaveClaimStillThrows`: today's no-receipt case, unchanged.

- [ ] **Step 2: Run the tests and confirm they fail**

- [ ] **Step 3: Implement**
  - Append the spec's style paragraph verbatim to the developer message.
  - Collect every non-nil `outputs[index]` into a `var toolOutputs: [String]` that lives across the loop.
  - In the final branch, keep the existing `ungroundedConfirmation` guard. Then compute `allowed` from `[developer message] + toolOutputs` and `stored.receipts`.
  - If `CoachReplyCheck.passes`, use `response.text`. Otherwise use `coachCommittedSummary` when there are receipts, or `CoachReplyLines.factLine(...)` built from the reads in `requestedProgress`, `requestedGoals`, `requestedWorkouts` and `requestedPreferences`.
  - Delete the summary-appending blocks.
  - Change the fixture's final text to `"All set."`

- [ ] **Step 4: Rewrite the dependent assertions.**
  - Assertions that expect true facts in `assistantText` (`"2027-01-15"`, `"3 piece"`, `"420"`, `"70 kg"`, `"1500"`) now assert those facts on `receipts` / `CoachCommittedReceipt`, or on the fact line for read-only turns.
  - Keep every `contains("9999") == false`.
  - Leave the `nil`, clarification and timeline-identity assertions alone.
  - Run `grep -rn "assistantText" ios/MivuTests` and check that each hit has been reviewed.

- [ ] **Step 5: Run `MivuTests` (unit target only) and confirm it passes.** Record the count.

- [ ] **Step 6: Commit**

`git commit -m "feat(coach): show checked prose instead of fact dumps"`

---

### Task 5: Reply rendering and follow-up chips

**Files:**
- Modify: `ios/Mivu/Coach/CoachView.swift:3-15` (new closures), `:254-258` (reply text), `:466-490` (chips after the cards)
- Modify: `ios/Mivu/Diary/TodayView.swift:331-338` (pass `openToday: { selectedTab = "today" }` and `openProgress: { selectedTab = "progress" }`)
- Modify: `docs/superpowers/plans/2026-10-23-siri-coach.md` Task 5 (one note: the notification body uses `String(AttributedString(markdown:…).characters)`)
- Test: `ios/MivuTests/CoachReplyLinesTests.swift`

**Interfaces:**
- Produces:
  - `CoachReplyLines.attributed(_ text: String) -> AttributedString`, which falls back to plain text.
  - `CoachReplyLines.plain(_ text: String) -> String`.
  - `CoachReplyLines.followUps(for turn: CoachExchangeSummary) -> [CoachFollowUp]`, where `enum CoachFollowUp { case today, progress }`.

- [ ] **Step 1: Write the failing tests**
  - `plain("About **1,240** kcal")` is `"About 1,240 kcal"`.
  - An unbalanced `"**x"` returns its text without crashing.
  - `followUps` returns `.today` for a completed turn with a meal receipt and `.progress` for one with a weight receipt. Both receipts give `[.today, .progress]`. A turn that is not completed gives `[]`. The read-only progress chip is dropped, per the spec's allowance.
- [ ] **Step 2: Run the tests and confirm they fail**
- [ ] **Step 3: Implement**
  - Render `Text(CoachReplyLines.attributed(reply))` and keep the `coachReply` identifier.
  - Show chips only on the latest exchange, as bordered buttons with `frame(minHeight: 44)`, labelled "See today" and "See progress", with identifiers `coachFollowUp-today` and `coachFollowUp-progress`.
- [ ] **Step 4: Run the tests and confirm they pass**
- [ ] **Step 5: Commit**

`git commit -m "feat(coach): inline emphasis and follow-up chips"`

---

### Task 6: Today-styled meal card and weight chip

**Files:**
- Modify: `ios/Mivu/Coach/CoachReceiptView.swift`
- Modify: `ios/Mivu/Coach/CoachView.swift:467` (also render weight receipts)
- Test: `ios/MivuTests/CoachReceiptPresentationTests.swift`, `ios/MivuUITests/CoachUITests.swift:190-235`

**Interfaces:**
- Consumes: from Task 2, `weightValue` and `weightUnit`.
- Produces:
  - `CoachReceiptPresentation.itemRows: [(name: String, amount: String, kcal: String)]`, where kcal is `"—"` when unknown.
  - `CoachReceiptPresentation.macroShare: (carbs: Double, protein: Double, fat: Double)?`, the energy share using 4/4/9 kcal per gram. It is nil when any total is unknown.
  - `CoachReceiptPresentation.weightLabel: String?`, for example `"Weight saved · 73.6 kg"`.

- [ ] **Step 1: Write the failing presentation tests**
  - `itemRowsShowEveryDishWithKcal`: 7 items → 7 rows, with an unknown item showing `"—"`.
  - `macroShareNilWhenAnyUnknown`.
  - `macroShareSumsToOne`.
  - `weightLabelUsesCommittedValue`.
- [ ] **Step 2: Run the tests and confirm they fail**
- [ ] **Step 3: Implement the view**
  - Replace the `.padding(12)` / `diarySurface` background with `DiarySummaryCardStyle` (the modifier, not the list-row helper).
  - Header: status in `SubmissionState.color`, then the date, then Review / Edit.
  - Large kcal line, with the Estimated tag.
  - A one-line split `Capsule` bar in `diaryCarbs`, `diaryProtein` and `diaryFat`, with a grams legend.
  - Rows: an `HStack` with name, amount and trailing monospaced kcal. At accessibility sizes they become a `VStack`. Each row is one `.accessibilityElement(children: .combine)` with the label `"{name}, {amount}, {kcal} calories"`.
  - Keep every existing identifier on its equivalent element. The disclosure keeps the per-item gram macros.
  - Weight chip: a `Capsule` in `diaryWeight` with a checkmark, identifier `coachWeightChip`.
  - Workout keeps today's content on the new surface.
- [ ] **Step 4: Update the UI tests** at `CoachUITests.swift:198-229` so their fact checks target `coachWeightChip` and the receipt elements instead of `coachReply`. Add `mealCardListsEveryDish` with a 5-item fixture meal. Check Dynamic Type at accessibility XXL.
- [ ] **Step 5: Run the unit tests, then the Coach UI tests that were changed** (`CoachUITests`, `CoachCorrectionUITests`, `CoachHistoryUITests` receipt cases), and confirm they pass.
- [ ] **Step 6: Commit**

`git commit -m "feat(coach): Today-styled receipt card and weight chip"`

---

### Task 7: Contract and verification record

**Files:**
- Modify: `docs/development/coach-chat-behavior.md:76-104`
- Create: `docs/verification/2026-10-23-coach-reply.md`

- [ ] **Step 1: Update the contract** with the spec's exact two replacements: the macro bar is visible, and checked prose is allowed.
- [ ] **Step 2: Run the full native unit suite and the focused Coach UI tests with XcodeBuildMCP.** Record the SHA, the simulator, the counts and the result bundle paths in the verification file. List any blocked gates honestly.
- [ ] **Step 3: Commit**

`git commit -m "docs(coach): reply contract and verification record"`
