# Android App Shell, Today, Manual Entry and Sample Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Android Mivu a usable diary on the phone. That means the four-tab
native shell, the Today screen in direction B, manual nutrition entry, and
sample mode with the composer and a local analysis worker. All of it is built
on the milestone 2 store.

**Architecture:**
- One `MainActivity` hosts Compose with typed Navigation routes and a Material 3
  short `NavigationBar` with four tabs: Today, Diary, Progress and Coach.
- Diary, Progress and Coach show an "Arrives in a later update" screen until
  their milestones land. Their parity rows stay `pending`.
- A process-wide `DiaryRepository` owns the single `DiaryDatabase` per
  profile, as the store's KDoc requires. It exposes `StateFlow` read models
  to `ViewModel`s.
- Day and nutrition math is pure Kotlin in `com.yakov103.mivu.diary`, ported
  from iOS.
- The UI lives in `com.yakov103.mivu.ui`.

**Tech Stack:** Kotlin, Compose Material 3 (Expressive components where
stable), Navigation Compose with type-safe routes, `androidx.lifecycle`
ViewModel and `StateFlow`, the platform photo picker, JUnit, and the Compose UI
test library.

**Spec:** [`docs/superpowers/specs/2026-10-23-android-app-design.md`](../specs/2026-10-23-android-app-design.md),
plus the approved mockups:
- [direction B](../../verification/android-design/android-mockups.png) for Today
  and Coach;
- [Diary/detail/entry](../../verification/android-design/android-diary-mockups.png)
  for the manual entry dialog. These are owner-review pending, built per the
  owner's go-ahead.

## Global Constraints

- Behaviour, copy and rules come from this checkout's iOS code. The key iOS
  files are:
  - `ios/Mivu/Diary/TodayView.swift`
  - `DiaryStyle.swift`
  - `DiaryViewModel.swift`
  - `ManualNutrition.swift`
  - `ManualNutritionView.swift`
  - `MealComposerView.swift`
  - `SampleAnalyzer.swift`
  - `DiaryDatabaseManualNutrition.swift`
  - `DiaryDatabaseMealMutations.swift` (`startDay`, `captureProjection`)
  - `DiaryReadModels.swift`
  - `DiaryModels.swift` (`nutritionTotals`)
  - `ios/Mivu/Progress/ProgressAnalytics.swift` (`daily`)
- Copy is iOS's English strings. Replace the word "iPhone" with "phone", for
  example "Saved on this phone".
- Native Android look, direction B:
  - Material 3 Expressive, edge-to-edge, short `NavigationBar` with labels on
    every item, `TopAppBar` titles.
  - Colours from `design-system/mivu/precision-glass/tokens.json`, in light,
    dark and high-contrast versions. Dynamic colour is off.
  - Material Symbols Rounded icons, via the `material-icons-extended` or
    vector assets: Today `restaurant`, Diary `menu_book`, Progress
    `bar_chart`, Coach `chat_bubble`, profile `account_circle`.
- Accessibility:
  - 48 dp minimum touch targets.
  - Every control has a content description that matches the iOS spoken
    label.
  - Font scale up to 200% stacks content and never clips it.
  - The system "Remove animations" setting is honoured.
  - The Compose `testTag` equals the iOS accessibility identifier, for
    example `logMeal`, `addManually`, `mealRow`, `todayDayActions`,
    `startNewDay`, `todayGoalSummary`, `manualFoodName` and
    `saveManualNutrition`.
- Every write goes through the store's `transaction(expectedRevision)`.
  There is exactly one `DiaryDatabase` per profile, per process.
- Sample mode exists only in debug builds. It is turned on by the intent
  extra `sampleMode=true`, or by the instrumentation runner. Release builds
  never contain it.
- Synthetic data only in tests. Local builds only. Commit as the owner, with
  no tool or assistant names.

## Review Focus

1. **The first launch on a clean install** creates "My diary" and shows
   Today. A failure shows "Couldn't create your diary" with "Try again". It
   never shows a blank screen. (Task 1)
2. **A meal with an unknown macro** shows "—" for that macro and the
   "Some nutrients are unknown…" note, never 0. (Tasks 2 and 5)
3. **Rotating, or killing the process, during manual entry** keeps the typed
   values. Saving twice after a retry creates one meal. (Task 6)
4. **Font scale 200% on Today** shows every number, with no clipping, and
   the tab labels stay visible. (Task 5)
5. **A sample-mode capture saved while offline, with the app then killed**
   gets its sample estimate on the next launch. (Task 4)

---

### Task 1: Theme, app shell and profile bootstrap

**Files:**
- Create: `android/app/src/main/java/com/yakov103/mivu/ui/theme/MivuTheme.kt`
- Create: `android/app/src/main/java/com/yakov103/mivu/ui/MivuApp.kt`
- Create: `android/app/src/main/java/com/yakov103/mivu/diary/DiaryRepository.kt`
- Create: `android/app/src/main/java/com/yakov103/mivu/MivuApplication.kt`
- Modify: `MainActivity.kt`, `AndroidManifest.xml`
- Test: `android/app/src/androidTest/java/com/yakov103/mivu/ui/AppShellTest.kt`, `android/app/src/test/java/com/yakov103/mivu/ui/theme/MivuThemeTest.kt`

**Interfaces:**
- Produces:
  - `MivuTheme(content)`, which builds `lightColorScheme` and
    `darkColorScheme` from the token hexes:
    - primary = accent;
    - surface and background = surface and canvas;
    - secondaryContainer = `#CCE8E7` (light) or a dark equivalent derived
      from the tokens;
    - custom `MivuColors(protein, carbs, fat, warning, success, summarySurface)`
      via a `CompositionLocal`;
    - high-contrast variants used when the system contrast level is above 0.
  - `class DiaryRepository(context)`, a singleton held by `MivuApplication`,
    with:
    - `suspend fun bootstrap(): Bootstrap`, which is `Ready(profileID)` or
      `Failed`. It lists `filesDir/profiles`, picks the stored selected
      profile, or creates "My diary" with the device time zone via
      `DiaryDatabase.create` when there are none.
    - `fun database(profileID): DiaryDatabase`, which caches one per
      profile.
    - `val changes: SharedFlow<Unit>`, emitted after every commit.
  - `@Serializable sealed interface Route` with `Today`, `Diary`, `Progress`,
    `Coach` and `ManualEntry(dayID: String?, mealID: String?)`.

- [ ] **Step 1: Failing tests.**
  - JVM `MivuThemeTest`: the light primary is `0xFF006D75` and the dark
    primary is `0xFF63D5CD`. Copy the token values from `tokens.json`.
  - Instrumented `AppShellTest`:
    - a fresh install shows the "Today" title and four nav items labelled
      Today, Diary, Progress and Coach;
    - the profile action has the content description "Profile and
      settings";
    - a forced bootstrap failure (test seam) shows "Couldn't create your
      diary" and a "Try again" button;
    - back from the Diary tab returns to Today.
- [ ] **Step 2: Run** `./gradlew :app:testDebugUnitTest --tests '*MivuThemeTest'` and the instrumented class. Expected: FAIL.
- [ ] **Step 3: Implement.** The selected tab is saved with
  `rememberSaveable`. `DataStore` is not needed: store the selected profile
  in a `SharedPreferences` key `selectedProfile`, excluded from backup.
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(android): add the Material 3 app shell and diary bootstrap`.

### Task 2: Day and nutrition math

**Files:**
- Create: `android/app/src/main/java/com/yakov103/mivu/diary/DiaryMath.kt`
- Test: `DiaryMathTest.kt` (JVM)

**Interfaces:**
- Produces:
  - `data class NutritionTotals(kcal: Double?, carbs: Double?, protein: Double?, fat: Double?, unknownItemCount: Int)`
    and `fun nutritionTotals(items: List<FoodItem>): NutritionTotals`. A
    macro is null when any item lacks it, as in iOS `DiaryModels.swift:360`.
  - `fun dayNutritionTotals(meals: List<DiaryMeal>, complete: Boolean): NutritionTotals`,
    which uses saved meals only, as in iOS `DiaryReadModels.swift:167`.
  - `data class DailyProgress(...)` and
    `fun dailyProgress(snapshotDays: List<TrackingDay>, meals: List<DiaryMeal>, goals: List<GoalRecord>, workouts: List<WorkoutSession>, localDate: String): DailyProgress`.
    It covers only the fields Today shows: `foodTotals`, `goal`,
    `remainingFromRecorded` and `exerciseAdjustedKcalRemaining`, as in iOS
    `ProgressAnalytics.daily`.
  - `fun goalOn(date: String, goals: List<GoalRecord>): GoalRecord?`, as in
    iOS `goal(on:)`.

- [ ] **Step 1: Failing tests:**
  - `allKnownSums`;
  - `oneMissingMacroMakesThatTotalNull` (unknownItemCount 1);
  - `unsavedMealsExcluded`;
  - `emptyCompleteDayIsZero`;
  - `remainingIsTargetMinusRecorded`;
  - `aboveGoalIsNegativeRemaining`;
  - `exerciseCreditAddsWorkoutBurnOnlyWhenEnabled`;
  - `goalOnPicksLatestEffectiveOnOrBefore`.

  The values are computed by hand in each test.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(android): port day totals and goal progress`.

### Task 3: Store operations for days, manual nutrition and meal capture

**Files:**
- Create: `android/app/src/main/java/com/yakov103/mivu/diary/DiaryDays.kt`, `ManualNutritionStore.kt`, `MealCapture.kt`
- Test: `android/app/src/androidTest/java/com/yakov103/mivu/diary/DiaryDaysTest.kt`, `ManualNutritionStoreTest.kt`, `MealCaptureTest.kt`

**Interfaces:**
- Produces, on `DiaryDatabase`. Each is ported one to one from the named iOS
  function, including its validation and errors:
  - `startDay(at: Instant, expectedRevision): TrackingDay` and
    `dayAssignment(at)` (iOS `startDay` / `dayAssignment`);
  - `saveManualNutrition(payload: ManualNutritionPayload, expectedRevision): ManualNutritionSaveResult`,
    `prepareManualNutritionTarget(choice, at)` and
    `manualNutritionResult(payload)` (iOS `DiaryDatabaseManualNutrition.swift`).
    It includes the frozen payload fingerprint and the reconcile that stops
    a retry from duplicating.
  - `captureProjection(text, photos, reviewFirst, dayID, at, dateOnly, submissionID, expectedRevision): DiaryMeal`
    (iOS `captureProjection`, without Coach mirroring).
- Consumes: `transaction`, the `Tx` puts and `DiaryError` from milestone 2.

- [ ] **Step 1: Failing instrumented tests:**
  - `startDayCreatesActiveDayInZone`;
  - `manualCreateSavesUserProvenanceItem`;
  - `manualRetryWithSamePayloadReturnsSameMeal`;
  - `manualRetryWithChangedPayloadRejected`;
  - `manualAppendToSavedMealBumpsRevision`;
  - `captureSavesSubmissionCapturedBeforeAnalysis`;
  - `captureRetrySameSubmissionIdIdempotent`.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(android): start days, save manual nutrition and capture meals`.

### Task 4: Sample analyzer and local analysis worker

**Files:**
- Create: `android/app/src/main/java/com/yakov103/mivu/analysis/SampleAnalyzer.kt`
- Create: `android/app/src/debug/java/com/yakov103/mivu/SampleMode.kt` (debug-only switch), plus the release no-op `android/app/src/release/java/com/yakov103/mivu/SampleMode.kt`
- Create: `android/app/src/main/java/com/yakov103/mivu/analysis/MealAnalysisWorker.kt`
- Test: `SampleAnalyzerTest.kt` (JVM), `MealAnalysisWorkerTest.kt` (instrumented)

**Interfaces:**
- Produces:
  - `object SampleAnalyzer { fun analyze(input: AnalysisInput): AnalysisOutput }`.
    It is an exact port: the apple estimate is 95 kcal, 25 g carbs, 0.5 g
    protein and 0.3 g fat; a note containing "half" or "חצי" scales by 0.5;
    the first number in the note sets the quantity, between 0 and 100,000;
    sources are `.sample`.
  - `data class AnalysisInput(...)`, ported from iOS `AnalysisInput` and
    `analysisInput`, with only the fields SampleAnalyzer reads.
  - `object SampleMode { val enabled: Boolean }`, which is always false in
    release.
  - `class MealAnalysisWorker(repository, analyzer: (AnalysisInput) -> AnalysisOutput)`
    with `suspend fun drain(profileID)`. It runs `nextPendingMealSubmission`,
    then `prepareAnalysis`, the analyzer, and `applyAnalysis`, until there is
    nothing left.
  - The app calls `drain` on start and after each capture. WorkManager comes
    in milestone 5 with live analysis.

- [ ] **Step 1: Failing tests.**
  - JVM: `noItemsGivesSampleApple`, `halfNoteScales`, `numberSetsQuantity`,
    `hebrewHalfScales`, `invalidLanguageRejected`.
  - Instrumented: `drainAppliesSampleToCapturedMeal`,
    `drainAfterReopenFinishesCapturedMeal` (the Review Focus 5 path with the
    process simulated by reopening) and `drainSkipsCancelled`.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** Expected: PASS, and a release APK scan shows no
  `SampleAnalyzer` caller wired in.
- [ ] **Step 5: Commit** `feat(android): add sample analysis and the local analysis worker`.

### Task 5: Today screen

**Files:**
- Create: `android/app/src/main/java/com/yakov103/mivu/ui/today/TodayViewModel.kt`, `TodayScreen.kt`, `MealRow.kt`, `NutritionViews.kt`
- Test: `android/app/src/test/.../ui/today/TodayViewModelTest.kt`, `android/app/src/androidTest/.../ui/today/TodayScreenTest.kt`

**Interfaces:**
- Produces:
  - `TodayUiState`, built from the repository read model: `displayDate`,
    `kcal`, `protein`, `carbs`, `fat`, `unknownNote`, `goal`, `meals`,
    `sampleMode` and `savedReceipt`.
  - `MealRow(meal, prominent)`, shared with the Diary tab later.
  - `TodayScreen(onOpenMeal, onLogWithPip, onAddManually, onLogMeal)`.
- The layout follows direction B and iOS `TodayView`:
  - The sample banner shows only in sample mode.
  - The summary card holds:
    - the date menu chip (`todayDayActions`, label "Day actions, <date>",
      single item "Start new day", `startNewDay`);
    - Pip art at 186 dp, or 144 dp at large text, using the static
      `pip.png` until milestone 7;
    - kcal in 52 sp bold, "—" when null, over "kcal recorded";
    - "No meals recorded" when there is no active day;
    - Protein, Carbs and Fat columns with coloured dots and "NN g";
    - the unknown-nutrients note;
    - the goal block (`todayGoalSummary`): "<T> kcal goal", "N to goal",
      "N above goal" or "Not estimated yet", a progress bar and the
      exercise-adjusted line.
  - Meals: the "Meals" header, the empty card "Your first meal starts here"
    / "Add photos or a note.", and `MealRow` items (`mealRow`), newest first.
  - The bottom bar is pinned above the navigation bar:
    - normally "Log with Pip" (`logMeal`), which opens the Coach tab, and
      "Add manually" (`addManually`);
    - in sample mode a single "Log meal" (`logMeal`).
- `MealRow` follows iOS `DiaryStyle.swift:238`:
  - a 56 dp thumbnail from the first photo (decoded off the main thread),
    otherwise a `restaurant` icon;
  - a title, then the time and " · Estimated", or the state title in the
    state colour;
  - "NNN kcal" when saved;
  - a 4 dp macro bar;
  - "Needs review" announced for meals awaiting review.

- [ ] **Step 1: Failing tests.**
  - JVM `TodayViewModelTest`: the state for a fixture day with known and
    unknown macros, a goal both above and below target, and an empty day.
  - Instrumented `TodayScreenTest`:
    - every listed tag exists;
    - kcal shows "—" when null;
    - Start new day calls the store;
    - "Add manually" opens `ManualEntry`;
    - "Log with Pip" selects the Coach tab;
    - at 2.0 font scale (`Density(fontScale = 2f)`) every node in the
      summary card is displayed and not clipped
      (`assertIsDisplayed` plus bounds within the screen).
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** Expected: PASS. Capture light, dark and 200%
  screenshots of the emulator Today screen into
  `docs/verification/android-today/`, generated with the sample fixture.
- [ ] **Step 5: Commit** `feat(android): build the Today screen`.

### Task 6: Manual nutrition entry

**Files:**
- Create: `android/app/src/main/java/com/yakov103/mivu/ui/manual/ManualNutritionDraft.kt`, `ManualNutritionScreen.kt`, `ManualNutritionViewModel.kt`
- Test: `ManualNutritionDraftTest.kt` (JVM), `ManualNutritionScreenTest.kt` (instrumented)

**Interfaces:**
- Produces:
  - `ManualNutritionDraft`, ported from iOS `ManualNutritionDraft.item()`:
    - a comma is treated as a decimal point;
    - the amount must be greater than 0;
    - each nutrient must be a finite number from 0 to 10,000,000;
    - at least one nutrient is required;
    - the item has provenance `.user`, reference "Entered manually", and
      per-nutrient `.user` sources only for the nutrients filled in.
  - `ManualNutritionScreen`, a full-screen dialog route per the mockup:
    - the top bar has Close and Save (`saveManualNutrition`), and Cancel is
      `cancelManualNutrition`;
    - outlined fields `manualFoodName`, `manualAmount` (default "1"),
      `manualUnit` (default "serving"), `manualCalories`, `manualProtein`,
      `manualCarbs` and `manualFat`, with the placeholder "Unknown" and a
      decimal keyboard;
    - the footer copy from iOS;
    - the "Recorded day" row when a day target is given;
    - "Discard changes?" with "Discard changes" and "Keep editing" on back
      or close when the form has changed;
    - the "View previously saved food" (`reconciledManualFood`) result.
  - The draft and the frozen payload, including the IDs made when the draft
    starts, survive rotation and process death via `SavedStateHandle`.

- [ ] **Step 1: Failing tests.**
  - JVM: `commaDecimal`, `zeroAmountRejected`, `noNutrientRejected`,
    `blankMeansUnknownZeroMeansZero`, `sourcesOnlyForFilled`.
  - Instrumented:
    - `saveCreatesMealShownOnToday`;
    - `discardDialogOnBackWhenDirty`;
    - `recreateKeepsValues`, using `ActivityScenario.recreate()`;
    - `doubleSaveAfterFailureCreatesOneMeal`, with the store failure
      injected on the first save.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(android): enter nutrition manually`.

### Task 7: Sample-mode meal composer

**Files:**
- Create: `android/app/src/main/java/com/yakov103/mivu/ui/composer/MealComposerScreen.kt`, `MealComposerViewModel.kt`
- Test: `MealComposerScreenTest.kt` (instrumented)

**Interfaces:**
- Produces `MealComposerScreen`, ported from iOS `MealComposerView`, as a
  full-screen dialog:
  - the "Log meal" title and the sample banner;
  - a text field `mealText` (4–10 lines);
  - photos from the system photo picker (`PickMultipleVisualMedia`), JPEG
    re-encoded, longest side at most 2048 px, kept under 10 MB;
  - the "Waking day" row;
  - the toggle "Review before saving totals" (`reviewFirst`);
  - "Enter nutrition manually" (`enterNutritionManually`), which opens
    Task 6;
  - Save (`sendMeal`), with a progress indicator while saving;
  - Discard with the iOS copy.

  On save it calls `startDay` if no day is active, then `captureProjection`,
  then `MealAnalysisWorker.drain`.

- [ ] **Step 1: Failing tests:**
  - `textOnlySaveShowsSampleAppleOnToday`;
  - `photoPickerResultSaved`, with the picker stubbed through Espresso
    Intents and a synthetic JPEG;
  - `emptySaveDisabled`;
  - `reviewFirstShowsAwaitingReview`.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(android): log meals in sample mode`.

### Task 8: Evidence and parity

**Files:**
- Create: `docs/verification/2026-10-24-android-today.md`
- Modify: `docs/parity.md`

- [ ] **Step 1: Run** the whole connected suite once and `:app:testDebugUnitTest`.
  Record the SHA, the emulator, the counts and the screenshot paths.
- [ ] **Step 2: Update the parity rows.**
  - `today` → Android `partial`. Notes: Pip art is static until
    milestone 7; the morning check-in and weight row arrive with milestone 6.
  - `meal-edit` → manual entry is in. Mark it `partial` and list what is
    still missing (food editor, adjust total, move meal).
  - `sample-mode` → `done` if its tests pass.

  Each row gets evidence in the bracketed test format. Run
  `python3 scripts/ci/parity.py` and the `test_parity` suite.
- [ ] **Step 3: Commit** `docs(verification): record Android Today and manual entry`.
