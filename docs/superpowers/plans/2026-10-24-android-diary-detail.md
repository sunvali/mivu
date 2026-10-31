# Android Diary Tab and Meal Detail Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the Diary tab, meal detail, and every meal edit flow that iOS
has. The Diary tab has a week strip, a day summary with skip/count, meals and
workouts. The edit flows are food edit, delete food, delete photo, adjust
total, move meal, delete meal and mark reviewed. All of it is native Material
3 in direction B.

**Architecture:**
- The meal edit operations are new store functions in
  `com.yakov103.mivu.diary`, each a one-to-one port of the iOS function.
- The UI is in `com.yakov103.mivu.ui.diary` and `ui.meal`.
- Today rows and Diary rows both open the same `MealDetail` route.
- The week strip is a `HorizontalPager` with one page per week.

**Tech Stack:** Kotlin, Compose Material 3 (Expressive), Navigation with typed
routes, `HorizontalPager`, the M3 `DatePicker`, ModalBottomSheet and
full-screen dialogs, JUnit and Compose UI tests.

**Spec:** [`docs/superpowers/specs/2026-10-23-android-app-design.md`](../specs/2026-10-23-android-app-design.md),
with the mockup [Diary/detail/entry](../../verification/android-design/android-diary-mockups.png).
Owner review of the mockup is pending; it is being built on the owner's
go-ahead.

## Global Constraints

- Behaviour, copy, rules and identifiers follow this checkout's iOS code:
  - `ios/Mivu/Diary/HistoryView.swift`
  - `DiaryWeekStrip.swift` (`DiaryWeekStrip`, `DayStatusChip`)
  - `MealDetailView.swift` (`MoveMealSheet`, `ScaleMealSheet`,
    `FoodItemEditor`, `MealPhotoViewer`)
  - `DiaryDatabaseMealMutations.swift` (`editItem`, `deleteItem`,
    `scaleMeal`, `deletePhoto`, `moveMeal`, `setCompleteness`)
  - `DiaryDatabaseScreenQueries.swift` (`diaryWeek`)
  - `ios/Mivu/Progress/ProgressAnalytics.swift` (`status`)
- The Compose testTag equals the iOS identifier, for example
  `diaryWeekStrip`, `diaryDayPill`, `diaryDayStatusChip`, `chooseDiaryDate`,
  `applyDiaryDate`, `diaryAskPip`, `diaryAddMenu`, `enterNutritionForDay`,
  `historyMeal`, `retryDiaryHistory`, `viewMealPhoto`, `editItem`,
  `correctMeal`, `addFoodManually`, `adjustMealTotal`, `mealTargetKcal`,
  `mealPreviewKcal`, `saveMealTotal`, `deleteMeal`, `confirmDeleteFood`,
  `deleteFood`, `acceptReview`, `mealAskPip`, `moveMealDestination` and
  `confirmMoveMeal`.
- Copy is iOS English, with "iPhone" replaced by "phone".
- Look and feel follows direction B:
  - native back and predictive back, swipe-to-dismiss rows where iOS swipes;
  - destructive actions in the error colour, confirmed with an M3
    `AlertDialog` that uses the iOS titles and messages;
  - targets at least 48 dp, TalkBack labels equal to iOS, 200% font size
    stacks without clipping.
- Every write goes through `transaction(expectedRevision)`, and each edit
  carries the meal revision it read, as iOS does. A stale edit shows "Could
  not complete action" and the screen reloads; it never overwrites.
- Read models never hold photo bytes. Photos load by ID off the main
  thread, reusing the Today `photoBytes` path and cache.
- Ask Pip entry points (`diaryAskPip`, `mealAskPip`, `askPipFood`) switch to
  the Coach tab with no draft until milestone 4. Note this in the parity
  notes.
- Workout rows display read-only. "Add weight manually" and "Add workout
  manually" arrive with milestone 6 editors and are hidden until then.
- Synthetic data only. Local builds only. Commit as the owner, with no tool
  or assistant names.

## Review Focus

1. **Editing a food while analysis applies to the same meal**: one of them
   gets StaleRevision and the user sees a message. No edit is lost. (Task 2)
2. **Moving a meal to a day that is later skipped**: the totals and status
   of both days update. (Tasks 1 and 4)
3. **Deleting the last food**: the button is hidden as on iOS, because a
   saved meal must keep at least one item. (Task 2)
4. **The week strip at the earliest record and on today**: swiping stops at
   the bounds and future days are disabled. (Task 3)
5. **Process death on meal detail with the food editor open**: the editor
   restores, or closes safely without saving a half edit. (Task 5)

---

### Task 1: Diary queries and day status

**Files:**
- Create: `android/app/src/main/java/com/yakov103/mivu/diary/DiaryQueries.kt`
- Test: `DiaryQueriesTest.kt` (instrumented) and `DayStatusTest.kt` (JVM)

**Interfaces:**
- Produces:
  - `data class DiaryDaySummary(day: TrackingDay?, localDate: String, mealCount: Int, savedMealCount: Int, pendingMealCount: Int, totals: NutritionTotals)`
    and `fun DiaryDatabase.diaryWeek(from: String, through: String): List<DiaryDaySummary>`,
    ported from iOS `diaryWeek`. It reads no photo bytes.
  - `fun DiaryDatabase.dayDetail(dayID): DayDetail` (meals sorted by
    `eatenAt` ascending, workouts, morning weight, goal) and
    `fun DiaryDatabase.earliestRecordDate(): String?`.
  - `enum DayStatus { Open, Closed, Skipped }` and
    `fun dayStatus(days, activeDayID, hasSavedFood): DayStatus`, ported from
    iOS `ProgressAnalytics.status`.
  - `fun DiaryDatabase.setCompleteness(dayID, completeness, expectedRevision)`,
    ported from iOS `setCompleteness`.

- [ ] **Step 1: Failing tests.**
  - JVM: `untrackedIsSkipped`, `activeIsOpen`, `savedFoodClosed`,
    `noFoodSkipped`.
  - Instrumented:
    - `weekSummariesCountMealsAndPending`;
    - `weekReadsNoPhotoBytes`;
    - `dayDetailSortsByEatenAt`;
    - `setCompletenessBumpsRevisionAndChangesStatus`.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(android): query diary weeks and day status`.

### Task 2: Meal edit operations

**Files:**
- Create: `android/app/src/main/java/com/yakov103/mivu/diary/MealEdits.kt`
- Test: `MealEditsTest.kt` (instrumented)

**Interfaces:**
- Produces functions on `DiaryDatabase`. Each is an exact port of the iOS
  function of the same name, including validation, revision checks and
  receipts or undo where iOS has them:
  - `editItem(mealID, item, explicitNutrients, reviewSubmissionID, expectedRevision)`
  - `deleteItem(mealID, itemID, expectedRevision)`
  - `scaleMeal(mealID, targetKcal, expectedRevision)`
  - `deletePhoto(mealID, photoID)`
  - `moveMeal(mealID, toDayID, eatenAt, expectedRevision, expectedDayID)`
- Consumes the Tx primitives, `editMealItems` and `deleteMeal` from earlier
  milestones. They are reused, not duplicated.

- [ ] **Step 1: Failing tests, one per function**, each with the success
  case, the stale-revision case and the iOS edge case:
  - `editItemRecomputesNutritionFromBasis`;
  - `deleteLastItemRejected`;
  - `scaleMealHitsTargetKcal`;
  - `scaleMealUnknownKcalRejected`;
  - `deletePhotoKeepsMealAndRepairsTurns`;
  - `moveMealToAnotherDayUpdatesBothTotals`;
  - `moveToTombstonedOrMissingDayRejected`;
  - `staleRevisionNeverOverwrites`.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(android): edit, scale, move and delete meal contents`.

### Task 3: Diary tab

**Files:**
- Create: `android/app/src/main/java/com/yakov103/mivu/ui/diary/DiaryViewModel.kt`, `DiaryScreen.kt`, `WeekStrip.kt`, `DaySummaryCard.kt`
- Modify: `ui/MivuApp.kt` (Diary tab content, `MealDetail(mealID)` route), `ui/today/MealRow.kt` (row click, `prominent` flag)
- Test: `DiaryViewModelTest.kt` (JVM) and `DiaryScreenTest.kt` (instrumented)

**Interfaces:**
- Produces `DiaryScreen` per the mockup and iOS `HistoryView`:
  - The top bar has the "Diary" title and these actions:
    - Choose date (`chooseDiaryDate`): an M3 `DatePickerDialog`, limited to
      the earliest record through today, with "Show date"
      (`applyDiaryDate`);
    - Ask Pip (`diaryAskPip`);
    - Add to this day (`diaryAddMenu`), a menu with "Enter nutrition
      manually" (`enterNutritionForDay`) that opens `ManualEntry` with the
      day;
    - profile.
  - The week strip (`diaryWeekStrip`):
    - It is a pager of weeks that starts on the locale's first day of the
      week.
    - Each day is a pill (`diaryDayPill`, state description the
      `yyyy-MM-dd` date) showing the letter, the number and a status dot.
    - Future days are disabled.
    - Swiping keeps the same weekday and clamps to today.
    - The spoken label follows iOS, for example "Monday 12 October, Open,
      2 meals".
  - The day summary card shows the "EEEE, d MMMM" title and a
    `DayStatusChip` (`diaryDayStatusChip`) with a menu containing "Skip This
    Day" or "Count This Day" and the note "Skipped days stay out of your
    statistics."
    - Its nutrition summary is "Recorded intake": kcal at 48 sp in the
      accent colour, and macros with one decimal.
    - It shows the target line and the morning weight.
  - Meals (`historyMeal`) use `MealRow(prominent = false)`, which opens
    `MealDetail`. Empty days show "No meals recorded for this day."
  - Workouts show "Workout — N minutes", read-only.
  - Empty, loading and error states: "Nothing logged" / "Ask Pip to add what
    you ate on this day." with a progress indicator, the error text and
    "Retry" (`retryDiaryHistory`).
  - Today rows also open `MealDetail`.

- [ ] **Step 1: Failing tests.**
  - JVM: the week page range, the clamp to today, and the pill labels.
  - Instrumented:
    - `selectingPillShowsDay`;
    - `futurePillDisabled`;
    - `skipDayChangesChipAndStatus`;
    - `chooseDateJumpsToWeek`;
    - `addMenuOpensManualEntryForDay`;
    - `todayRowOpensMealDetail`.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** Expected: PASS. Capture light, dark and 200%
  screenshots to `docs/verification/android-diary/`.
- [ ] **Step 5: Commit** `feat(android): build the Diary tab`.

### Task 4: Meal detail

**Files:**
- Create: `android/app/src/main/java/com/yakov103/mivu/ui/meal/MealDetailViewModel.kt`, `MealDetailScreen.kt`, `MealPhotoViewer.kt`
- Test: `MealDetailScreenTest.kt` (instrumented)

**Interfaces:**
- Produces `MealDetailScreen` per the mockup and iOS `MealDetailView`:
  - an edge-to-edge photo hero at 240 dp (`viewMealPhoto`) that opens
    `MealPhotoViewer` with pinch zoom and delete;
  - a summary card with the title, the time or "Time unspecified", "Saved on
    this phone", and the state text and messages from iOS;
  - "Adjust total" (`adjustMealTotal`);
  - the "Review estimate" section with "Mark reviewed" (`acceptReview`)
    when a review is pending;
  - "Attached photos" when there is more than one;
  - the Foods list:
    - each row shows the name, "qty unit", the uncertain note, kcal and an
      Ask Pip icon;
    - tapping a row opens `FoodItemEditor` (`editItem`);
    - swipe to delete (`deleteFood`) works only on saved meals with more
      than one food, and is confirmed with `confirmDeleteFood`;
  - "Add note or photo" (`correctMeal`), sample mode only until Coach;
  - "Add food manually" (`addFoodManually`);
  - the Meal actions menu: Move to another day, Retry analysis (sample
    mode), and Delete meal (`deleteMeal`) with the iOS confirm copy;
  - a bottom "Ask Pip about this meal" (`mealAskPip`).
- "Meal unavailable" / "It may have been deleted or belong to another
  profile." is shown when the meal is gone.

- [ ] **Step 1: Failing tests:**
  - `showsFoodsAndTotals`;
  - `deleteFoodConfirmsAndRemoves`;
  - `deleteFoodHiddenForSingleFood`;
  - `deleteMealConfirmsAndReturns`;
  - `photoViewerDeleteKeepsMeal`;
  - `markReviewedSavesProposal`;
  - `deletedMealShowsUnavailable`.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** Expected: PASS, plus light and dark screenshots.
- [ ] **Step 5: Commit** `feat(android): show and manage a meal`.

### Task 5: Food editor, adjust total and move meal

**Files:**
- Create: `android/app/src/main/java/com/yakov103/mivu/ui/meal/FoodItemEditor.kt`, `ScaleMealSheet.kt`, `MoveMealSheet.kt`
- Test: `MealEditorsTest.kt` (instrumented)

**Interfaces:**
- Produces:
  - `FoodItemEditor`, a full-screen dialog that reuses `CaptureDialog`. It
    is ported from iOS `FoodItemEditor` with the same fields, validation,
    preview (`foodPreviewCalories`), Save (`saveItem`) and "Delete meal"
    (`deleteMealFromFood`).
  - `ScaleMealSheet`, an M3 ModalBottomSheet with the target kcal
    (`mealTargetKcal`), the preview (`mealPreviewKcal`) and Save
    (`saveMealTotal`).
  - `MoveMealSheet`, a bottom sheet titled "Move meal". It has the
    destination waking-day list (`moveMealDestination`) and Move
    (`confirmMoveMeal`). It shows the "Moved to <date>" receipt
    (`movedMealDayReceipt`).
  - Editor drafts survive rotation and process death.

- [ ] **Step 1: Failing tests:**
  - `editFoodSavesAndUpdatesTotals`;
  - `staleEditShowsMessageAndReloads`;
  - `scaleToTargetUpdatesFoods`;
  - `moveMealShowsReceiptAndMovesTotals`;
  - `editorSurvivesRecreate`.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(android): edit foods, adjust totals and move meals`.

### Task 6: Evidence and parity

- [ ] **Step 1: Run** the whole connected suite plus unit, lint and
  `assembleRelease` once, and record
  `docs/verification/2026-10-24-android-diary.md` with the SHA, emulator,
  counts and screenshots.
- [ ] **Step 2: Update the parity rows:**
  - `diary` → `partial`, noting that Ask Pip waits for Coach and the weight
    and workout editors arrive with milestone 6;
  - `meal-edit` → `done` if every edit flow is tested;
  - `sample-mode` stays `partial` until camera capture.

  Run the parity checks.
- [ ] **Step 3: Commit** `docs(verification): record the Android Diary tab and meal detail`.
