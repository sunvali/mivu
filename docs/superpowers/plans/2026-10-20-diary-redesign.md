# Diary Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Diary tab, day content and meal detail look like Today, put food editing where the food is, and keep every edit reachable through Coach, including a new single-food delete.

**Architecture:** Data first (delete-food store operation, its Coach tool, a week-range history query, a Coach draft handoff), then shared views (week strip, coverage chip, meal row), then the two screen rewrites. Screens reuse `diarySummaryCard`, `NutritionSummary`, `DiaryCaptureAction`, `MealRow`, `FoodItemEditor` and `diaryCorrectedItem`; no new dependency.

**Tech Stack:** Swift 6, SwiftUI (iOS 26), SQLite via `DiaryDatabase`/`DiaryTransaction`, Swift Testing (`MivuTests`), XCTest UI tests (`MivuUITests`).

**Spec:** `docs/superpowers/specs/2026-10-20-diary-redesign-design.md`

## Global Constraints

- Work in worktree `../mivu-diary-redesign`, branch `feat/diary-redesign`; Conventional Commit messages; no mention of tools/assistants in commits or PR.
- Every manual edit in the redesigned Diary has a Coach path through the same store operation and revision checks; a manual control without one does not ship.
- Precision Glass tokens and semantic colors only (`Color.diary*`); Liquid Glass only on navigation and controls; 20-pt content inset; 44-pt minimum targets; 52-pt primary actions.
- Dynamic Type through accessibility sizes, VoiceOver labels, Reduce Motion, Increase Contrast, Reduce Transparency; English only.
- Unknown nutrition renders "—", never zero; never invent or store a day for an empty date.
- Focused test command, `<SUITE>` replaced per task (simulator UUID reserved for this branch):
  `xcodebuildmcp simulator test --project-path "$PWD/ios/Mivu.xcodeproj" --scheme Mivu --simulator-id <UUID> --derived-data-path "$PWD/build/smoke/DerivedData" --json '{"extraArgs":["-testPlan","Mivu","-only-testing:<SUITE>","-parallel-testing-enabled","NO"]}' --output json`
  `TEST(X)` below means this command with `<SUITE>` = `X`. Pass = zero failures and a non-zero test count.
- Parity audit (done while planning): `edit_item`, `append_food`, `accept_review`, `move_meal`, `delete_meal`, `attach_photos`, `delete_photo`, `retry_meal`, `set_day_coverage`, weight and workout tools already cover every other Diary control ("I ate half" = `edit_item` quantity). `delete_item` (Task 2) closes the only gap.

## Review Focus

1. Ask Pip prefill while the Coach composer already holds unsent text: the person's text must survive (Task 4 test `prefillNeverOverwritesUnsentText`).
2. Deleting a food from a meal that is still awaiting review, or whose revision moved since the sheet opened: stale revision is refused with nothing changed (Task 1 test `staleRevisionDeletesNothing`).
3. Coach replaying a `delete_item` turn after a crash: the food is removed once and a single receipt exists (Task 2 test `deleteItemReplayRemovesOnce`).
4. Two recorded days with the same local date in different time zones (travel): both show on the selected date, not one silently dropped (Task 3 test `weekKeepsSameDateDaysFromBothZones`).
5. Profile switch while a non-today date is selected: selection resets to today and no stale day content renders (Task 6 UI test `profileSwitchResetsSelectedDay`).

---

### Task 1: Delete one food (store)

**Files:**
- Modify: `ios/Mivu/Diary/DiaryDatabaseMealMutations.swift` (add transaction wrapper next to `editItem` at ~113, and `DiaryTransaction.deleteItem` next to `editItem` at ~400)
- Modify: `ios/Mivu/Diary/DiaryStore.swift` (next to `editItem` at ~387)
- Create: `ios/MivuTests/DiaryDeleteItemTests.swift`

**Interfaces:**
- Produces: `DiaryStore.deleteItem(mealID: UUID, itemID: UUID, expectedRevision: Int, expectedProfileID: UUID?) throws`; `DiaryTransaction.deleteItem(mealID: UUID, itemID: UUID, expectedRevision: Int?) throws`; `DiaryDatabase.deleteItem(mealID:itemID:expectedRevision:expected:maximumBytes:) -> DiaryCommit<Void>`.

- [ ] **Step 1: Write failing tests** in `DiaryDeleteItemTests` (Swift Testing, build the store with the same fixture pattern as `CoachManualEngineTests.fixture()`/`savedMeal`, with a saved meal of two items "Toast" 120 kcal and "Egg" 80 kcal):
  - `deletesOneFoodAndBumpsRevision`: after delete of Toast, export snapshot meal has items `["Egg"]`, revision `+1`, meal totals kcal `80`, and a saved submission with text `"Direct item delete"`.
  - `staleRevisionDeletesNothing`: `expectedRevision: revision - 1` throws `DiaryError.staleRevision`; items still `["Toast","Egg"]`.
  - `lastFoodCannotBeDeleted`: one-item meal throws `DiaryError.invalidData`; item kept.
  - `unknownItemThrowsNotFound`: random `itemID` throws `DiaryError.notFound`.
- [ ] **Step 2: Run** `TEST(MivuTests/DiaryDeleteItemTests)`. Expected: compile failure, `deleteItem` missing.
- [ ] **Step 3: Implement.** `DiaryTransaction.deleteItem` reads `mealItems(id:)`, guards `count > 1` (`invalidData`) and index exists (`notFound`), then records a saved `MealSubmission(text: "Direct item delete", …)` with an `AnalysisOutput` of the remaining items exactly as `editItem` does, and persists via `commitSavedItems(mealID:items:expectedRevision:)` (it checks revision and bumps it). Wrappers mirror `editItem`'s `transaction(...)` and `pagedMutation(...)`.
- [ ] **Step 4: Run** the same suite. Expected: 4 passed.
- [ ] **Step 5: Commit** `feat(diary): delete a single food from a meal`.

### Task 2: `delete_item` Coach tool

**Files:**
- Modify: `ios/Mivu/Coach/CoachManualEdits.swift` (enum case, `mealID`, `target`, schema in `manualSchemas`, `parseManual`)
- Modify: `ios/Mivu/Coach/CoachWriteFingerprint.swift:~38`
- Modify: `ios/Mivu/Diary/DiaryDatabaseCoachMutations.swift` (`validateReplay` ~90, preflight ~150, `applyManual` ~314)
- Test: `ios/MivuTests/CoachEditParityTests.swift`, `ios/MivuTests/CoachManualEngineTests.swift`

**Interfaces:**
- Consumes: `DiaryTransaction.deleteItem(mealID:itemID:expectedRevision:)` (Task 1).
- Produces: `CoachManualEdit.deleteItem(mealID: UUID, itemID: UUID, revision: Int)`; target string `"delete_item/\(mealID)/\(itemID)"`; tool name `delete_item` with args `meal_id`, `item_id`, `expected_revision` (all required).

- [ ] **Step 1: Write failing tests.**
  - Parity: add `"delete_item"` to the name list in `manualEditsHaveDeclaredCoachOperations`.
  - `CoachEditParityTests.deleteItemRejectsOnlyFood`: parsing `delete_item` against a `CoachContext.Meal` with one item throws `CoachError.invalidArguments`.
  - `CoachManualEngineTests.deleteItemRemovesOneFood`: two-item saved meal; run `delete_item` for one item; snapshot meal has one item, receipt `mealID`/`dayID` set.
  - `CoachManualEngineTests.deleteItemReplayRemovesOnce`: same structure as `moveThenDeleteMealKeepsTombstoneAndRetryDoesNotRestoreIt` (first run hits `limitExceeded`, retry replays): item count stays 1, turn has exactly 1 receipt.
  - `CoachManualEngineTests.staleDeleteItemChangesNothing`: `expected_revision: 999_999` leaves both items.
- [ ] **Step 2: Run** `TEST(MivuTests/CoachEditParityTests)` and `TEST(MivuTests/CoachManualEngineTests)`. Expected: new tests fail.
- [ ] **Step 3: Implement.** Schema description: `"Delete one explicitly requested food from a retrieved saved meal using its real item ID and meal revision. If it is the meal's only food, do not call this; use ask_clarification to ask whether to delete the whole meal."` Parse requires the meal in context and the item in `meal.items`, and `meal.items.count > 1`. Fingerprint arguments `["item": itemID.uuidString, "revision": revision]`. Preflight checks `meal(id, revision:)` and item presence; replay is valid when the item is absent from `mealItems(id:)`; apply calls `deleteItem(mealID:itemID:expectedRevision: nil)` and fills the receipt like `.item`.
- [ ] **Step 4: Run** both suites. Expected: all pass, including existing fingerprint test `quantityOnlyCorrectionKeepsLegacyFingerprint` unchanged.
- [ ] **Step 5: Commit** `feat(coach): delete a single food by conversation`.

### Task 3: Week-range history query

**Files:**
- Modify: `ios/Mivu/Diary/DiaryDatabaseScreenQueries.swift`, `ios/Mivu/Diary/DiaryStore.swift`, `ios/Mivu/Diary/DiaryReadModels.swift`
- Test: `ios/MivuTests/DiaryDatabaseTests.swift`

**Interfaces:**
- Produces: `struct DiaryWeekPage: Equatable, Sendable { var days: [DiaryDaySummary]; var earliestLocalDate: String? }`; `DiaryStore.diaryWeek(from: String, through: String, expectedProfileID: UUID) throws -> DiaryWeekPage` (inclusive `yyyy-MM-dd`, span ≤ 7 dates else `invalidData`).

- [ ] **Step 1: Write failing tests** `weekReturnsOnlyDaysInRange` (days on 2027-01-10, -12, -18; query 01-11…01-17 → only 01-12; `earliestLocalDate == "2027-01-10"`), `weekRejectsSpanOverSevenDays`, `weekKeepsSameDateDaysFromBothZones` (two days 2027-01-12 in `Asia/Jerusalem` and `America/New_York` → both returned).
- [ ] **Step 2: Run** `TEST(MivuTests/DiaryDatabaseTests)`. Expected: compile failure.
- [ ] **Step 3: Implement** inside `domainRead`, filtering `json_extract(CAST(payload AS TEXT), '$.localDate') BETWEEN ? AND ?` and mapping rows through `DiaryTransaction.daySummary` like `diaryHistory`; `earliestLocalDate` via `MIN(...)` over `day`.
- [ ] **Step 4: Run.** Expected: pass.
- [ ] **Step 5: Commit** `feat(diary): week-range day summaries`.

### Task 4: Ask Pip draft handoff

**Files:**
- Modify: `ios/Mivu/Coach/CoachTimelineModels.swift:120`, `ios/Mivu/Coach/CoachNavigationOwner.swift`, `ios/Mivu/Coach/CoachView.swift:135`, `ios/Mivu/Coach/CoachViewModel.swift`, `ios/Mivu/Diary/TodayView.swift` (`coachAction(from:)`)
- Test: `ios/MivuTests/CoachNavigationTests.swift`

**Interfaces:**
- Produces: `CoachNavigationRequest.target: CoachSeekTarget?` and `.draft: String?`; `CoachNavigationOwner.queue(_ target: CoachSeekTarget?, draft: String? = nil, from:selection:isChangingProfile:) -> Bool`; `OpenDiaryCoachAction.callAsFunction(_ target: CoachSeekTarget?, draft: String? = nil, expectedSelection:) -> Bool` (existing two-argument call sites keep compiling); `CoachViewModel.prefill(_ text: String) -> Bool` (sets `draft.text` only when it is empty after trimming; returns whether it did).
- Draft copy (exact): empty date `"For \(weekday), \(d MMM): "` e.g. `"For Tuesday, 14 Oct: "`; food `"About the \(item.name) in \(mealTitle): "`.

- [ ] **Step 1: Write failing tests** `queuedDraftReachesRequest` (queue `nil` target + draft → `request?.draft == "For Tuesday, 14 Oct: "`, `target == nil`), `prefillFillsEmptyDraft`, `prefillNeverOverwritesUnsentText` (draft "two eggs" stays, returns false).
- [ ] **Step 2: Run** `TEST(MivuTests/CoachNavigationTests)`. Expected: fail.
- [ ] **Step 3: Implement.** In `CoachView`'s request task, seek only when `target != nil`, then call `coach.prefill(draft)` when present, then consume.
- [ ] **Step 4: Run** `MivuTests/CoachNavigationTests` and `MivuUITests/CoachNavigationUITests`. Expected: pass.
- [ ] **Step 5: Commit** `feat(coach): open Coach with a prefilled draft`.

### Task 5: Shared Diary components

**Files:**
- Create: `ios/Mivu/Diary/DiaryWeekStrip.swift`
- Modify: `ios/Mivu/Diary/DiaryStyle.swift` (`MealRow`, add `CoverageChip`)
- Test: `ios/MivuTests/DiaryWeekStripTests.swift`

**Interfaces:**
- Produces: `enum DiaryWeek { static func dates(containing localDate: String, calendar: Calendar) -> [String] }` (7 `yyyy-MM-dd`, starting at `calendar.firstWeekday`); `DiaryWeekStrip(selected: Binding<String>, today: String, earliest: String?, summaries: [String: [DiaryDaySummary]], timeZoneID: String)`; `CoverageChip(completeness: DayCompleteness, set: (DayCompleteness) -> Void)`; `MealRow` keeps its initializer.
- Pill VoiceOver label (exact pattern): `"Tuesday 14 October, partial, 3 meals"`; empty day `"Tuesday 14 October, nothing logged"`.

- [ ] **Step 1: Write failing tests** `weekStartsOnCalendarFirstWeekday` (Monday-first calendar, 2027-01-14 → first `2027-01-11`, last `2027-01-17`), `weekCrossesYearBoundary` (2026-12-31 Sunday-first → contains `2027-01-02`), `pillLabelDescribesCoverageAndMeals`.
- [ ] **Step 2: Run** `TEST(MivuTests/DiaryWeekStripTests)`. Expected: fail.
- [ ] **Step 3: Implement.** Strip: horizontal `ScrollView` paged by week (`.scrollTargetBehavior(.paging)`), no pages after the week containing `today` or before `earliest`; pill = weekday letter, date number, coverage-colored dot (filled when recorded), today marked; paging animation off under Reduce Motion; pills stack text at accessibility sizes. `CoverageChip` is a `Menu` over `DayCompleteness.allCases` with one-line footer "Complete means all intake was recorded." `MealRow`: thumbnail 56 pt (or `fork.knife` icon), title, time, kcal trailing, thin protein/carbs/fat bar using `diaryProtein/diaryCarbs/diaryFat` (hidden when all unknown), `diaryWarning` dot + "Needs review" accessibility value when awaiting review.
- [ ] **Step 4: Run.** Expected: pass; also `TEST(MivuUITests/SummaryCardsUITests)` still passes with the new `MealRow`.
- [ ] **Step 5: Commit** `feat(diary): week strip, coverage chip and richer meal rows`.

### Task 6: Diary tab with inline day

**Files:**
- Modify: `ios/Mivu/Diary/HistoryView.swift` (rewrite `HistoryView`; remove `DayHistoryView` and `HistoryRoute` once no caller remains)
- Delete: `ios/Mivu/Diary/DiaryHistoryViewModel.swift`, `ios/MivuTests/DiaryHistoryViewModelTests.swift`, `ios/Mivu/Diary/DiaryHistoryUITestFixture.swift` if only paging tests use it
- Test: `ios/MivuUITests/DiaryUITests.swift` (and any UI test using `diaryDay`, `earlierDiaryDays`, `newerDiaryDays`, `latestDiaryDays`, `showAllDiaryDays`, `logMealForDay`, `diaryDayOpenChat`)

**Interfaces:**
- Consumes: `diaryWeek` (Task 3), `openDiaryCoach(_:draft:expectedSelection:)` (Task 4), `DiaryWeekStrip`, `CoverageChip`, `MealRow` (Task 5), existing `model.loadDay(_:)`/`model.dayDetail(_:)`.
- Accessibility identifiers (new): `diaryWeekStrip`, `diaryDayPill`, `diaryAskPip`, `diaryAddMenu`, `diaryCoverageChip`; kept: `chooseDiaryDate`, `applyDiaryDate`, `historyMeal`, `enterNutritionForDay`, `logWeightForDay`, `logWorkoutForDay`.

- [ ] **Step 1: Write failing UI tests** in `DiaryUITests`: `selectingPillShowsThatDaysMeals`, `calendarJumpSelectsDate`, `emptyDateShowsNothingLoggedAndOnlyAskPip` (no `logMealForDay`, `diaryAddMenu` disabled), `askPipOnEmptyDatePrefillsCoach` (Coach composer value starts `"For "`), `profileSwitchResetsSelectedDay`. Replace tests that drove the removed paging buttons.
- [ ] **Step 2: Run** `TEST(MivuUITests/DiaryUITests)`. Expected: new tests fail.
- [ ] **Step 3: Implement.** Layout per spec "Diary tab": `List` styled like `TodayView` (same insets, `listSectionSpacing(12)`, canvas); summary card = `NutritionSummary` + goal kcal if `activeGoal` + `CoverageChip` (hidden when the date has no recorded day) + weight; meals as `MealRow` cards pushing `MealDetailView`; workouts section when present. Bottom `safeAreaInset`: `DiaryCaptureAction` (Log meal, only when a recorded day exists; opens `MealComposerView(dayID:)`) beside an Ask Pip glass button (`.day(id)` seek, or `nil` + date draft when empty). Toolbar: leading calendar (existing sheet, now sets `selected`), trailing `+` menu (manual nutrition, morning weight, workout; disabled without a recorded day) and profile. Selected date defaults to today and resets on profile change.
- [ ] **Step 4: Run** `TEST(MivuUITests/DiaryUITests)`, `TEST(MivuUITests/ManualNutritionUITests)`, `TEST(MivuUITests/CoachNavigationUITests)`. Expected: pass.
- [ ] **Step 5: Commit** `feat(diary): week strip Diary with inline day`.

### Task 7: Meal detail and food edit sheet

**Files:**
- Modify: `ios/Mivu/Diary/MealDetailView.swift` (`MealDetailView` body, `itemRow`, `FoodItemEditor`)
- Test: `ios/MivuUITests/DiaryAmountEditorUITests.swift`, `ios/MivuUITests/CoachCorrectionUITests.swift`

**Interfaces:**
- Consumes: `DiaryStore.deleteItem` (Task 1), `openDiaryCoach(_:draft:expectedSelection:)` (Task 4), `diaryCorrectedItem(_:previous:explicitNutrients:)` for the live preview.
- Identifiers: kept `editItem`, `itemQuantity`, `itemCalories`, `deleteMeal`, `halfPortion`, `correctMeal`; new `deleteFood`, `askPipAboutFood`, `foodMoreDetails`, `mealAskPip`.

- [ ] **Step 1: Write failing UI tests** `editSheetPreviewScalesWithAmount` (2→4 pieces doubles previewed kcal before Save), `deleteFoodRemovesRowAfterConfirm`, `onlyFoodOffersDeleteMealInstead` (no `deleteFood`; a "Delete meal" button instead), `askPipAboutFoodPrefillsCoach` (composer starts `"About the "`).
- [ ] **Step 2: Run** `TEST(MivuUITests/DiaryAmountEditorUITests)`. Expected: fail.
- [ ] **Step 3: Implement** per spec "Meal detail" and "Food edit sheet": photo hero (tap → `MealPhotoViewer`), header with title/time/large kcal/macro bars, review banner holding the existing Mark reviewed action beside the estimate label, food card rows (name, amount+unit, kcal) opening the sheet, "Record history" disclosure last, bottom Ask Pip (`.turn(sourceTurnID)` when the meal has a source turn, else `.day(dayID)`); `…` menu unchanged. Sheet: `.presentationDetents([.medium, .large])`; amount + unit first, preview row from `diaryCorrectedItem`, `DisclosureGroup("More details")` holding name + nutrients + source, Delete food (confirmation dialog) or Delete meal when it is the only food, Ask Pip (dismiss sheet, open Coach with food draft). Save keeps `editItem` with `expectedRevision`.
- [ ] **Step 4: Run** `DiaryAmountEditorUITests`, `CoachCorrectionUITests`, `MivuTests/DiaryAmountEditTests`. Expected: pass.
- [ ] **Step 5: Commit** `feat(diary): photo-led meal detail and quick food edit`.

### Task 8: Native verification record

**Files:**
- Create: `docs/verification/2026-10-20-diary-redesign.md`

- [ ] **Step 1: Run** the full plan (`-testPlan Mivu`, no `-only-testing`) on the reserved simulator; record the exact source SHA, simulator/runtime, passed/failed/skipped counts and result bundle path.
- [ ] **Step 2: Capture** simulator screenshots of Diary (today, past day, empty date), meal detail and food edit sheet in light and dark, plus Diary at accessibility XXXL; store under `docs/verification/diary-redesign/`.
- [ ] **Step 3: Write** the record; list any blocked gate honestly (physical-device VoiceOver/haptics not run).
- [ ] **Step 4: Commit** `docs(verification): diary redesign native evidence`.
