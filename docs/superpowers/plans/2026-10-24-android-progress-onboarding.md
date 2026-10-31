# Android Progress, Onboarding and Day Rollover Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring Android to iOS parity for milestone 6:
- the chart-first Progress tab and its detail screens;
- the Pip-hosted setup that sets daily targets;
- automatic waking-day rollover with the morning check-in on Today and Coach;
- the weight, workout and goal editors;
- the per-device day cutoff and the opt-in morning reminder;
- diary reports as PDF or CSV.

**Architecture:** This is milestone 6. Most of the data side exists already:
- `DiaryDays` has the waking-day rules;
- `DiaryMath` and `DiaryQueries` have daily totals, day status and week reads;
- `CoachReads.coachProgress` is the `ProgressAnalytics` port;
- `ProgressWrites` and `CoachWrites` hold the weight, workout, goal and profile
  transaction writes.

This milestone does not add storage. It does four things:
- exposes those transaction writes as `DiaryDatabase` operations, the way iOS
  `DiaryStore` does;
- widens `coachProgress` into the iOS display path (`progressRange` with
  `includeDailyReports`);
- ports the pure `ProgressInsights` and `OnboardingTargets` logic;
- builds the screens on top.

The day cutoff becomes a per-device preference that the existing functions
read. The editors are Material 3 full-screen dialogs. Charts are Compose
`Canvas`. Reports use the platform `PdfDocument` and the share sheet. The
reminder uses `AlarmManager` and `NotificationCompat` from `androidx.core`.

**Tech Stack:** Kotlin and Jetpack Compose:
- Material 3: `SingleChoiceSegmentedButtonRow`, `DatePickerDialog`,
  `TimePicker`, `ExposedDropdownMenuBox`, `Switch`, `LinearProgressIndicator`;
- Compose `Canvas`, navigation-compose `dialog<>` routes, `SharedPreferences`;
- platform APIs: `AlarmManager.setWindow`, a `BroadcastReceiver`,
  `android.graphics.pdf.PdfDocument`, `FileProvider` and `Intent.ACTION_SEND`;
- `NotificationCompat` and `NotificationManagerCompat`, already in `core-ktx`;
- JUnit and Compose UI instrumented tests.

No new dependency.

**Spec:** [`docs/superpowers/specs/2026-10-23-android-app-design.md`](../specs/2026-10-23-android-app-design.md)
(feature map rows: onboarding, day rollover, Progress, Settings, reports and
notifications; "Android-specific quality rules"). Behaviour comes from these
iOS specs:
- [onboarding](../specs/2026-10-20-onboarding-design.md);
- [day rollover](../specs/2026-10-20-day-rollover-design.md);
- [Progress insights](../specs/2026-10-23-progress-insights-design.md).

The mockup is
[android-progress-mockup.png](../../verification/android-design/android-progress-mockup.png).

The scope comes from:
- [`docs/parity.md`](../../parity.md): the rows `progress`,
  `progress-chart-first`, `onboarding`, `day-rollover`, `reports` and
  `settings` (the daily-targets part);
- the open notes in `today` ("morning check-in and weight row", "Set a goal" /
  "Edit goals", the late-meal receipt), `diary` (weight and workout entry) and
  `pip` (Progress);
- [`android-carried-items.md`](android-carried-items.md), section "Settings and
  day rollover".

**iOS sources** (the source of truth; copy is verbatim, with "iPhone"
replaced by "phone"):
- `ios/Mivu/Progress/ProgressInsights.swift`: bands, ranges, buckets, trend,
  headline, burn, wins, calendar rows.
- `ios/Mivu/Progress/ProgressCards.swift`: `ProgressSnapshot` and the cards.
- `ios/Mivu/Progress/ProgressView.swift`:
  - the screen;
  - the weight and workout ledgers;
  - `WorkoutDetailView`;
  - the Pip requests.
- `ios/Mivu/Progress/ProgressDetailViews.swift`: detail screens and history
  paging.
- `ios/Mivu/Progress/ProgressEditorViews.swift`:
  - `GoalEditorValues`;
  - `GoalEditorView`;
  - `WeightCorrectionView`;
  - `WorkoutEditorView`;
  - `MorningWeightEditorView`.
- `ios/Mivu/Diary/DiaryDatabaseProgressQueries.swift`: `topFoods`,
  `hasDays(before:)` and `progressRange`.
- `ios/Mivu/Diary/DiaryDatabaseScreenQueries.swift` `screenRecords` (65), and
  `DiaryStore.swift` 403–450, 559–575 and 708–717.
- `ios/Mivu/Onboarding/OnboardingTargets.swift` and `OnboardingView.swift`
  (commit `2450c71c`), with `ios/MivuTests/OnboardingTargetsTests.swift`.
- Day rollover and the morning check-in (commit `93fa727f`):
  - `ios/Mivu/Diary/MorningCheckInCard.swift`;
  - `DaySettingsSection.swift` (`DaySettingsSection`, `MorningReminder`);
  - `DiaryViewModel.swift` 248–270 (`loadMorningRecap`, `rollOverDay`,
    `saveMorningWeight`);
  - `TodayView.swift` 170–230 and 590–735, and 796–825 (`todayGoal`);
  - `ios/Mivu/Coach/CoachView.swift` 350–360.
- `ios/Mivu/Diary/DiaryDatabaseMealMutations.swift` 662 (`DayCutoff`).
- `ios/Mivu/Diary/DiaryReport.swift`, `DiaryReportPDF.swift` and
  `DiaryReportSettings.swift`.
- `ios/Mivu/Diary/SettingsView.swift` 40–60 (Setup rows) and 205 ("Share a
  report").
- `ios/Mivu/Diary/HistoryView.swift` 115–141 (the day menu's "Add weight
  manually" and "Add workout manually", and the workout rows).

## Scope decisions

**Kept:**
- **Rollover.**
  - Automatic rollover on app start and on every return to the foreground.
  - The per-device "Day starts at" hour (0–8). This settles the carried item
    "Port the per-device day-cutoff setting".
  - The late-meal receipt: "Added to <day>" and "Move to <day>".
- **Morning check-in.**
  - The Today card: recap, weigh-in, Skip, the done line and Close.
  - The compact Coach bubble with "Tell Coach instead".
  - The Today "Morning weight" row and the goal entry ("Set a goal" / "Edit
    goals"). These settle the carried item "Add the morning check-in, the
    weight row and the goal editor".
- **Editors.**
  - Weight: "Add weight manually", for today or a chosen day, and "Edit
    weight".
  - Workouts: the workout editor and workout detail (edit, delete, Ask Pip).
  - Goals: the goal editor with its effective date and history.
  - Entry points: Today, Progress, the Diary day menu and Settings.
- **Progress.**
  - Week, Month, 3M and Year.
  - The headline card with the period bars, the weight card and the
    average-day donut.
  - The "More" rows (Calendar, Calories, Estimated burn, Top foods, Workouts,
    Goals), each opening a detail screen with history paging.
  - The weight and workout ledgers.
  - Pip presenting, with the chart card and glasses.
- **Onboarding.**
  - Six steps: hello, about you, your goal, how you eat, connect ChatGPT and
    results.
  - It runs on first launch of a new diary, and from Settings "Redo setup
    with Pip".
- **Settings rows:** "Your day" (day start, Morning check-in, reminder time),
  then under "Setup": "Goals", "Redo setup with Pip" and "Backup & export".
- **Reports:** "Share a report" with PDF or CSV, through the share sheet.

**Decided, each with its reason:**
- **The day cutoff is an app-wide value read from preferences, as iOS
  `DayCutoff.hour`.**
  - `DAY_CUTOFF_HOUR` becomes `object DayCutoff { const val KEY = "dayStartHour"; @Volatile var hour = 4 }`.
  - `MivuApplication.onCreate` loads it from `DiaryRepository.preferences`,
    and the Settings picker writes both the preference and `DayCutoff.hour`.
  - `wakingDateLabel` and `CoachEngine.wakingDayInstruction` default to
    `DayCutoff.hour`. Their existing `cutoffHour` parameter keeps tests
    deterministic.
  - The `shortcut:` comment in `DiaryDays.kt` is replaced by iOS's one: "a
    per-device preference read by the store; move it into the profile if
    days must agree across devices."
- **Rollover runs from `MainActivity.onStart`,** the Android analogue of
  iOS's scene becoming active.
  - Rotation also calls `onStart`. That is harmless, because a repeated start
    reuses the open day (iOS rule).
  - `ProcessLifecycleOwner` would add a dependency for no gain.
- **The morning reminder is in scope, with `AlarmManager` and
  `NotificationCompat`.**
  - Why it is included: the iOS day-rollover spec has the reminder, and
    `day-rollover` is a baseline parity row.
  - Why it is cheap:
    - it is off by default;
    - it is one receiver and about 60 lines;
    - there is no foreground service and no exact-alarm permission;
    - the channel is reused by the meal-analysis notification row later.
  - **Scheduling.** `AlarmManager.setWindow(RTC_WAKEUP, next, 10 min)` is
    inexact, so it needs no `SCHEDULE_EXACT_ALARM`. The receiver posts the
    notification and schedules the next day.
  - It reschedules on `BOOT_COMPLETED`, `TIME_SET`, `TIMEZONE_CHANGED` and
    `MY_PACKAGE_REPLACED`. `RECEIVE_BOOT_COMPLETED` is a normal permission.
  - `JobScheduler` cannot target a time of day. WorkManager would be a new
    dependency, and the spec reserves `AlarmManager` for timed work.
  - **Permission.** On API 33 and above, `POST_NOTIFICATIONS` is requested
    only when the person turns the toggle on, as iOS asks only then. Below
    API 33 (minSdk 31–32) no prompt exists, so the code checks
    `NotificationManagerCompat.areNotificationsEnabled()` instead.
  - Denied: the toggle stays off and the footer says "Notifications are off
    for Mivu. You can allow them in Android Settings."
  - Tapping the notification opens the app where it was left. That is iOS
    behaviour; opening Today directly is a follow-up there too.
  - Real-phone delivery is `blocked` until a physical phone exists. Per the
    spec, emulator results do not prove notifications.
- **Progress Pip shows the props.**
  - `PipRigScene` gains iOS `showsProgressProps`: the `prop-chart*` parts and
    glasses are visible, and the held arm comes from
    `PipGestureLibrary.progressHeldArm`.
  - Six poses are added to `CompanionPose` (`PresentingCalm`,
    `PresentingCheer`, `ProgressEntrance`, `ProgressEntranceCheer`,
    `ProgressRange`, `ProgressTap`). They map to the existing `PipMoment`s.
  - Progress uses the `Today` framing.
  - This closes the parity `pip` note "Progress is pending". Today's moments
    stay in milestone 7.
- **Onboarding opens only for a diary this launch created.**
  - `Bootstrap.Ready` gains `created: Boolean = false`.
  - The shell opens `Route.Onboarding` once when it is true.
  - Existing diaries are never forced through setup (iOS rule).
  - If the process dies before setup ends, the next launch opens the diary
    normally. "Redo setup with Pip" in Settings is the way back, as on iOS.
- **Onboarding's ChatGPT call** goes through `ChatGPTConnection.inference()`.
  Its `tools` parameter becomes `JsonObject?`, which `ResponsesClient`
  already accepts, so the call sends no tools, as iOS passes `nil`. Without a
  connection the step offers "Use the estimate instead". The iOS "Use Apple
  Intelligence instead" has no Android counterpart.
- **Weights are stored in the unit typed.**
  - The morning check-in saves kilograms, rounded to 0.1, as iOS
    `saveMorningWeight`.
  - Its kg/lb menu is the per-device preference `weightUnit` (iOS
    `@AppStorage("weightUnit")`).
- **Reports read one `DiaryDatabase.snapshot()`.** iOS `snapshotForExport`
  does the same: export is the one path allowed a full snapshot.
  - Files go to `cacheDir/reports/<uuid>/` and are shared through a
    `FileProvider` (`${applicationId}.reports`).
  - The folder is deleted when the share sheet returns.
- **Reports live on a new "Backup & export" screen.** It has only "Share a
  report" for now. The archive export and import UI joins it with the
  Play-readiness item, which stays carried.

**Deferred or cut:**
- the iOS "Show in Dynamic Island" rows: `live-activity` is `n/a`;
- "Diary preferences", profiles, profile deletion and nutrition source:
  these are other Settings rows and stay carried;
- Coach reply and meal-analysis notifications: milestones 5 and 8;
- Today Pip moments: milestone 7;
- the "Record history" disclosure and "Log meal" for a past day: these are
  diary-row items outside this milestone.

## Global Constraints

- **Paths:** `A/` = `android/app/src/main/java/com/yakov103/mivu/`, `T/` =
  `android/app/src/test/java/com/yakov103/mivu/`, `I/` =
  `android/app/src/androidTest/java/com/yakov103/mivu/`.
- **Platform:**
  - minSdk 31, targetSdk 37;
  - platform and AndroidX APIs already in the catalog; no new dependency;
  - predictive back comes from navigation-compose.
- **Data:**
  - no schema change;
  - values are stored metric unless typed in lb, as on iOS;
  - day cutoff, `weightUnit`, `morningReminder`, `morningReminderMinutes`
    (default 480), `morningCardDismissedDay` and `morningWeightSkippedDay` are
    device preferences in `DiaryRepository.preferences` ("mivu", excluded from
    backup);
  - no write rebuilds a full snapshot, except reports;
  - every Progress read is bounded.
- **Ownership:** every screen load and save captures `profileID` at request
  time and drops its result if the selection changed, as the existing view
  models do.
- **Synthetic data only.** Fixtures use the synthetic diary in
  `I/ui/today/TodayFixture.kt` and `I/ui/diary/DiaryFixture.kt`: weights
  around 72–74 kg, a 2,100 kcal goal, and meals such as "two boiled eggs and a
  slice of toast". No real person's data and no live ChatGPT call in tests:
  onboarding uses a fake inference.
- **Accessibility:**
  - 48 dp minimum targets;
  - TalkBack labels match the iOS spoken labels ("Hide check-in", "Weight in
    kilograms", "Setup progress" valued "Step n of 6", "Intake toward that
    day's goal", "Calories by day");
  - every chart has a text summary and a `stateDescription`;
  - font scale 2.0 stacks rather than clips;
  - the system "Remove animations" setting gives Pip's still pose and
    fade-only card transitions.
- **Copy** (verbatim from iOS):
  - morning card:
    - "Good morning" / "Good afternoon" / "Good evening" (by hour: 5–11,
      12–17, else);
    - "Yesterday", "of <n> kcal", "Morning weight", "Skip", "Save";
    - "You're set for today", "<±x.x> <unit> this week";
    - Coach: "<greeting>. Weighed in yet?", "Tell Coach instead", which fills
      "My weight this morning is ";
  - late meal: "Added to <wakingDayTitle>" and "Move to <wakingDayTitle>";
  - Today: "Morning weight", "Log weight", "Set a goal", "Edit goals";
  - Settings:
    - "Your day", "Day starts at", "Morning check-in", "Reminder time";
    - the footer "Food before <h> still counts for the day before. A new day
      starts the first time you open Mivu after that.";
    - when denied, "Notifications are off for Mivu. You can allow them in
      Android Settings.";
    - "Setup", "Goals", "Redo setup with Pip", "Backup & export";
  - reminder: title "Good morning", body "Log your weight or breakfast.";
  - editors: the iOS titles, section headers, field labels, validation lines,
    discard alerts and save-error alerts in `ProgressEditorViews.swift`;
  - onboarding: every string in `OnboardingView.swift` 98–304;
  - Progress: every string in `ProgressInsights.swift`, `ProgressCards.swift`,
    `ProgressView.swift` and `ProgressDetailViews.swift`;
  - reports: every string in `DiaryReportSettings.swift` and
    `DiaryReportPDF.swift` ("Share a report", "Last 7 days", "Last 30 days",
    "All time", "Custom", "Share report", "Preparing report", "Could not
    prepare this report. Your local diary is preserved.").
- **Speed:**
  - each task runs only its own test classes, one class per
    `connectedDebugAndroidTest` run;
  - the full suite runs once, in Task 7;
  - reviews are batched after Task 3 and after Task 5, and the final review
    comes after Task 7.

  ```sh
  cd android
  ./gradlew :app:testDebugUnitTest --tests '*<Class>'
  ./gradlew :app:connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=com.yakov103.mivu.<pkg>.<Class>
  ```

## Review Focus

1. **The phone is opened at 03:30, then again at 04:10:**
   - at 03:30 nothing rolls over, and a meal goes to yesterday's waking day
     with an "Added to Yesterday" receipt;
   - at 04:10 exactly one new day starts, and further foregrounds reuse it;
   - changing "Day starts at" to 6 AM before 06:00 rolls nothing over.

   (Task 1: `rollOverStartsOneDayAfterTheCutoff`,
   `rollOverHonoursAChangedCutoff`, `lateMealReceiptOffersMove`)
2. **A weigh-in typed in pounds on the morning card**:
   - "160" with lb is saved as 72.6 kg;
   - the result reads "160.0 lb" back;
   - a value outside 20–400 kg keeps Save disabled.

   (Task 5: `poundsAreSavedAsKilograms`, `outOfRangeWeightCannotBeSaved`)
3. **Coach changes the goal while the goal editor is open:** Save shows
   "Could not save goals", keeps the typed targets, and never overwrites the
   newer revision. (Task 3: `staleGoalSaveKeepsTheDraft`)
4. **ChatGPT fails, answers nonsense, or is disconnected during onboarding**:
   - the estimate stays, marked "Estimate", with "ChatGPT couldn't answer just
     now…" and "Try again";
   - Pip plays recovery;
   - "Save my targets" still saves the estimate.

   (Task 6: `badReplyKeepsTheEstimate`, `failedRequestOffersRetry`)
5. **A report over a diary with formula-like or quoted meal text, or no
   meals**:
   - CSV cells starting with `=+-@` get a leading apostrophe;
   - quotes are doubled;
   - an empty range gives a PDF that says "No saved meals in this range."

   (Task 7: `csvNeutralisesFormulasAndQuotes`, `emptyRangeStillMakesAReport`)

---

### Task 1: Day cutoff, automatic rollover and the late-meal receipt

**Files:**
- Modify:
  - `A/diary/DiaryDays.kt` (`DayCutoff`, `rollOverDay`);
  - `A/coach/CoachEngine.kt` (the default from `DayCutoff.hour`);
  - `A/MivuApplication.kt` (load the cutoff; `rollOverDay()`);
  - `A/MainActivity.kt` (`onStart`);
  - `A/ui/today/TodayViewModel.kt` and `TodayScreen.kt` (the receipt);
  - `A/ui/MivuApp.kt` (pass the move action).
- Test:
  - `I/diary/DiaryDaysTest.kt`;
  - `T/coach/WakingDayInstructionTest.kt` (new; no test covers
    `CoachEngine.wakingDayInstruction` yet);
  - `I/ui/today/TodayScreenTest.kt`.

**Interfaces:**
- Consumes: `startDay`, `dayAssignment`, `moveMeal(mealID, toDayID, expectedRevision, expectedDayID)`
  and `DiaryRepository.preferences`.
- Produces:
  - `object DayCutoff { const val KEY = "dayStartHour"; @Volatile var hour: Int = 4; fun load(prefs: SharedPreferences); fun set(prefs: SharedPreferences, hour: Int) }`,
    where `set` clamps the hour to 0..8;
  - `fun DiaryDatabase.rollOverDay(at: Instant): TrackingDay?`. It returns
    null when there is no active day or `dayAssignment(at)` is `Existing`;
    otherwise it calls `startDay`. One transaction, retried once on
    `StaleRevision`, as `TodayViewModel.startNewDay`.
  - `fun MivuApplication.rollOverDay(): Job`. It waits for
    `Bootstrap.Ready`, then runs on IO.
  - `fun wakingDayTitle(localDate: String, relativeTo: String? = null): String`
    in `A/diary/DiaryDays.kt`, a port of iOS: "Yesterday", else e.g. "Tue,
    Oct 20" (`EEE, MMM d`, `Locale.US`).
  - `TodayUiState.lateReceipt: LateReceipt?`, with
    `data class LateReceipt(val added: String, val moveTo: String?)`. It is set
    when the receipt meal's day `localDate` is before
    `diaryDateLabel(meal.capturedAt, day.timeZoneID)`. `moveTo` is non-null
    only while that calendar date is still today's calendar date.
  - `fun TodayViewModel.moveToCalendarDay(mealID: UUID)`: `startDay(now)`,
    then `moveMeal(mealID, day.id, expectedRevision = meal.revision, expectedDayID = meal.dayID)`.

- [ ] **Step 1: Failing tests.**
  - `DiaryDaysTest`:
    - `wakingDateUsesTheCutoffAtTheBoundaries`: 01:30 → the previous date;
      04:00 exactly → today; 04:30 → today; cutoff 6 at 05:30 → the previous
      date;
    - `rollOverStartsOneDayAfterTheCutoff`: the active day is yesterday; at
      03:59 the result is null; at 04:10 one new day starts; a second call
      returns null; there is one new day row;
    - `rollOverHonoursAChangedCutoff` (`DayCutoff.hour = 6`; 05:00 → null);
    - `rollOverWithoutAnActiveDayDoesNothing`;
    - `rollOverAfterThreeDaysAwayStartsTodayOnly`: there are no days in
      between.
  - Waking-day instruction:
    `earlyMorningWindowFollowsTheCutoff(cutoffHour = 6)`, where 07:00 is
    inside the window and 05:30 outside.
  - `TodayScreenTest`:
    - `lateMealReceiptOffersMove`: a meal captured at 01:30 today on
      yesterday's waking day shows "Added to Yesterday" and "Move to
      <today>"; tapping it moves the meal to the calendar day;
    - `ordinaryReceiptStaysSavedOnThisPhone`.
- [ ] **Step 2: Run** them. Expected: FAIL (unresolved `DayCutoff`,
  `rollOverDay`, `lateReceipt`).
- [ ] **Step 3: Implement.**
  - `MainActivity.onStart` calls `app.rollOverDay()`.
  - `MivuApplication.onCreate` calls `DayCutoff.load(...)`.
  - The receipt keeps the existing `SavedReceipt` look, with the move action
    as a 48 dp `TextButton` with an `arrow_forward` icon.
- [ ] **Step 4: Run** those classes, then `CoachEngineTest`, `DiaryCaptureTest`
  and `ManualNutritionStoreTest`, since the cutoff default moved. Expected:
  PASS.
- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/java/com/yakov103/mivu android/app/src/test/java/com/yakov103/mivu/coach android/app/src/androidTest/java/com/yakov103/mivu/diary/DiaryDaysTest.kt android/app/src/androidTest/java/com/yakov103/mivu/ui/today/TodayScreenTest.kt
git commit -m "feat(android): roll over the waking day at a per-device cutoff"
```

### Task 2: Progress reads, editor writes and insights

**Files:**
- Create:
  - `A/diary/ProgressQueries.kt`;
  - `A/progress/ProgressInsights.kt` (bands, ranges, buckets, trend, headline,
    burn, wins, calendar rows, `ProgressSnapshot`).
- Modify:
  - `A/coach/CoachReads.kt`: `coachProgress` gains `includeDailyReports`, the
    91 and 365 spans, and the display fields;
  - `A/diary/ProgressWrites.kt` (the public operations).
- Test:
  - `I/diary/ProgressQueriesTest.kt`;
  - `T/progress/ProgressInsightsTest.kt`.

**Interfaces:**
- Consumes: `coachProgress`, `setWeight`, `createWorkout`, `deleteWeight`,
  `deleteWorkout`, `setGoal`, `exactGoal`, `effectiveGoal`, `updateProfile`,
  `startDay` and `resolveDay`.
- Produces:
  - **`CoachProgress`** gains defaulted fields: `dailyReports: List<CoachDailyProgress>? = null`,
    `displayWeights: List<CoachWeightReference>? = null`,
    `latestWeight: CoachWeightReference? = null`, `workoutTotal: Int? = null`
    and `savedFoodDates: List<String>? = null`. The Coach JSON is unchanged,
    because nulls are omitted, as the existing encoder does.
  - **`fun DiaryDatabase.progressRange(endingOn: String, days: Int, includeDailyReports: Boolean = false): CoachProgress`.**
    - Without `includeDailyReports`, days must be 1, 7 or 30, as the Coach
      allows.
    - With it, 91 and 365 are also allowed.
    - The horizon is `max(37, days)`.
    - It fills the display fields as iOS `progressRange` does.
  - **Page and food types:**
    - `data class TopFood(val name: String, val kcal: Double, val count: Int)`;
    - `fun DiaryDatabase.topFoods(from: String, through: String, limit: Int): List<TopFood>`,
      the iOS SQL verbatim;
    - `fun DiaryDatabase.hasDays(before: String): Boolean`;
    - `data class RecordPage<T>(val values: List<T>, val cursor: Long?, val hasMore: Boolean)`;
    - `fun DiaryDatabase.weightHistory(before: Long? = null): RecordPage<WeightEntry>`,
      `workoutHistory(before: Long? = null): RecordPage<WorkoutSession>` and
      `goalHistory(before: Long? = null): RecordPage<GoalRecord>`. These port
      iOS `screenRecords`: 30 a page, ordered by date, then ordinal, then id,
      descending.
  - **Store writes,** each one transaction at the current head and each a port
    of the `DiaryStore` method of the same name:
    - `recordWeight(value: Double, unit: String = "kg", at: Instant = Instant.now(), startNewDay: Boolean = true): WeightEntry`;
    - `updateWeight(id: UUID, value: Double, expectedRevision: Int): WeightEntry`;
    - `setWeight(dayID: UUID, value: Double, unit: String, expectedRevision: Int?): WeightEntry`;
    - `deleteWeight(id: UUID, expectedRevision: Int)`;
    - `createWorkout(localDate: String, draft: WorkoutDraft): WorkoutSession`;
    - `createWorkout(dayID: UUID, draft: WorkoutDraft): WorkoutSession`;
    - `updateWorkout(session: WorkoutSession, expectedRevision: Int): WorkoutSession`;
    - `deleteWorkout(id: UUID, expectedRevision: Int)`;
    - `setGoals(goal: GoalRecord, expectedRevision: Int?): GoalRecord`;
    - `goal(on: String, exact: Boolean = false): GoalRecord?`;
    - `updateProfile(profile: DiaryProfile, expectedProfile: DiaryProfile?)`.
  - **Insights,** in `A/progress/ProgressInsights.kt` (pure Kotlin, ports
    with the same names):
    - `enum class ProgressBand { Near, BitOff, Off, FarOff }`, with
      `companion fun of(kcal: Double?, target: Double?): ProgressBand?`
      (≤10%, ≤20%, ≤35%, else) and `val title`;
    - `enum class ProgressRange(val days: Int, val title: String) { Week(7,"Week"), Month(30,"Month"), Quarter(91,"3M"), Year(365,"Year") }`;
    - `data class ProgressBucket`, `ProgressCalendarDot`,
      `ProgressCalendarRow`, `TrendPoint`, `ProgressHeadline` (with `title`
      and `celebrates`), `BurnEstimate`, `BurnProgress` and `ProgressWin`;
    - `object WeightTrend { fun points(weights: List<CoachWeightReference>): List<TrendPoint> }`;
    - `object ProgressInsights`, with `band`, `burn`, `wins`, `buckets`,
      `plainResult`, `plainGap`, `plainMacro`, `calendarRows`, `slopePerDay`,
      `days` and `headline`;
    - `class ProgressSnapshot(progress: CoachProgress, range: ProgressRange, zone: String, today: String)`,
      with the iOS fields;
    - `companion fun loadDays(range: ProgressRange) = max(30, range.days)`.

- [ ] **Step 1: Failing tests.**
  - `ProgressInsightsTest` ports every case of iOS `ProgressInsightsTests`,
    using the same synthetic numbers and expected values, including:
    - `partialAndPendingDaysGetNoBandAndStayOutOfTheHeadline`;
    - `steadyLossReadsOnTrackDespiteTheSmoothedLag`;
    - `burnUsesTheWeighInSlopeNotTheLaggingTrend`;
    - `weekShowsSevenDaysButJudgesBurnAndWeightOnTheLoadedMonth`;
    - `proteinStreakIgnoresTodayWhileItIsUnfinished`.

    Each assertion is copied from the iOS test, with Kotlin syntax only.
  - `ProgressQueriesTest`:
    - `displayRangeAcceptsQuarterAndYearButCoachDoesNot`: `progressRange(…, 91)`
      throws `CoachError.InvalidArguments`; `progressRange(…, 91, true)`
      returns 91 `dailyReports`;
    - `yearLoadIsBounded`: 365 seeded synthetic days load in under 2 s on the
      emulator. This is recorded, not tuned, and is the iOS performance gate;
    - `topFoodsGroupsByNormalisedNameAndSkipsUnknownAndPending`;
    - `historyBeforeLooksPastEmptyWeeks` (`hasDays(before:)`);
    - `weightHistoryPagesThirtyAtATime`;
    - `recordWeightStartsADayOnlyWhenAsked`;
    - `staleGoalRevisionIsRejected`;
    - `createWorkoutForADateReusesThatDay`.
- [ ] **Step 2: Run** `ProgressInsightsTest` and `ProgressQueriesTest`.
  Expected: FAIL.
- [ ] **Step 3: Implement.** The Coach read path keeps calling
  `coachProgress(endingOn, days)` unchanged. Only `progressRange(…, true)`
  fills the display fields.
- [ ] **Step 4: Run** those classes, then `CoachReadsTest` and
  `CoachProgressWritesTest`. Expected: PASS, with no Coach JSON change.
- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/java/com/yakov103/mivu/diary android/app/src/main/java/com/yakov103/mivu/coach/CoachReads.kt android/app/src/main/java/com/yakov103/mivu/progress android/app/src/test/java/com/yakov103/mivu/progress android/app/src/androidTest/java/com/yakov103/mivu/diary/ProgressQueriesTest.kt
git commit -m "feat(android): add Progress reads, editor writes and insights"
```

### Task 3: Weight, workout and goal editors

**Files:**
- Create:
  - `A/ui/progress/WeightEditors.kt` (`WeightEditorScreen`, covering both
    "Add weight manually" and "Edit weight");
  - `A/ui/progress/WorkoutEditor.kt` (`WorkoutEditorScreen`,
    `WorkoutDetailScreen`);
  - `A/ui/progress/GoalEditor.kt` (`GoalEditorValues`, `GoalEditorScreen`);
  - `A/ui/progress/EditorViewModels.kt`.
- Modify:
  - `A/ui/MivuApp.kt`: the routes `WeightEditor(dayID: String?, weightID: String?)`,
    `WorkoutEditor(localDate: String, dayID: String?, sessionID: String?)`,
    `WorkoutDetail(sessionID)` and `Goals`, as `dialog<>` full-screen routes
    (`dismissOnBackPress = false`), as `ManualEntry` is;
  - `A/ui/today/TodayScreen.kt` and `TodayViewModel.kt`: the "Morning weight"
    row; "Set a goal" / "Edit goals" when there is no kcal target; remove the
    `shortcut:` comment;
  - `A/ui/diary/DiaryScreen.kt`: the day menu's "Add weight manually" and "Add
    workout manually"; workout rows open `WorkoutDetail`; remove the "Read-only
    until…" comment.
- Test:
  - `T/ui/progress/GoalEditorValuesTest.kt`;
  - `I/ui/progress/EditorsTest.kt`.

**Interfaces:**
- Consumes: the Task 2 store writes, `goalHistory` and `dayDetail`.
- Produces:
  - `data class GoalEditorValues(val localDate: String, val original: GoalRecord?, val kcal: String, val carbs: String, val protein: String, val fat: String, val weight: String, val exerciseCredit: Boolean)`,
    with `valid`, `hasEditedTargets`, `expectedRevision` and
    `fun record(zone: String): GoalRecord`. These are iOS's, with blank
    meaning null.
  - `fun progressNumber(text: String): Double?`, iOS `ProgressDate.number`:
    trimmed, accepting `.` or `,`, finite.
  - Route callers: `onEditGoals()`, `onAddWeight(dayID: UUID?)`,
    `onEditWeight(id)`, `onAddWorkout(localDate, dayID?)` and
    `onOpenWorkout(id)`.
- **Screens** (mockup row 3):
  - each is an M3 full-screen dialog: a `TopAppBar` with a Close icon, the
    title and a "Save" `TextButton`;
  - fields are `OutlinedTextField`s with `KeyboardType.Decimal`, or `Number`
    for minutes;
  - the validation line is shown as `supportingText` with `isError`;
  - Close with edits asks the iOS discard alert;
  - a failed save shows the iOS alert and keeps the draft.
- **Goals:**
  - the effective date is a read-only field opening `DatePickerDialog`;
  - changing the date with edits asks "Change the effective date?";
  - a history list of `goalHistory` ("Older goals" / "Latest goals");
  - the exercise credit is a `Switch`.
- **Workout:**
  - Strength / Cardio / Other is a `SingleChoiceSegmentedButtonRow`, stacked
    at font scale ≥ 1.5;
  - exercises have their sets;
  - the optional estimate keeps `burnSource` when unchanged, else
    `userEstimate`;
  - workout detail has "Edit", "Delete workout" (iOS confirmation copy) and
    "Ask Pip", as the Diary "Ask Pip" already does.

- [ ] **Step 1: Failing tests.**
  - `GoalEditorValuesTest`:
    - `blankFieldsAreNoTarget`;
    - `negativeOrTextIsInvalid`;
    - `commaDecimalIsAccepted`;
    - `recordKeepsTheOriginalID`;
    - `hasEditedTargetsIgnoresUntouchedFields`.
  - `EditorsTest` (Compose, on the synthetic fixture):
    - `todayWeightRowOpensAddWeightAndSaves`: it starts or reuses today's day
      and the row shows "72.5 kg";
    - `diaryDayMenuAddsWeightToThatDay`: other day labels are unchanged;
    - `editWeightUpdatesTheSameEntry` (the revision bumps);
    - `outOfRangeWeightShowsTheIosLine`;
    - `workoutSavesWithExercisesAndSets`;
    - `workoutDetailDeletesAfterConfirm`;
    - `setAGoalAppearsWithoutATargetAndSaves`: Today then shows "2,100 kcal
      goal";
    - `staleGoalSaveKeepsTheDraft`: a concurrent `setGoals` bumps the
      revision; Save shows "Could not save goals", and the fields keep the
      typed values;
    - `closeWithEditsAsksToDiscard`;
    - `editorTargetsAtLeast48dpAtFontScale2`.
- [ ] **Step 2: Run** those classes. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** those classes, `TodayScreenTest` and `DiaryScreenTest`.
  Expected: PASS.
- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/java/com/yakov103/mivu/ui android/app/src/test/java/com/yakov103/mivu/ui/progress android/app/src/androidTest/java/com/yakov103/mivu/ui/progress
git commit -m "feat(android): add weight, workout and goal editors"
```

**Review batch 1** (Tasks 1–3) runs here.

### Task 4: Progress tab, detail screens and Pip presenting

**Files:**
- Create:
  - `A/ui/progress/ProgressScreen.kt` (the screen and `ProgressViewModel`);
  - `A/ui/progress/ProgressCards.kt` (headline, weight, macros, "More" rows);
  - `A/ui/progress/ProgressCharts.kt` (Canvas bars with stepped target, trend
    line with dots, donut, calendar grid);
  - `A/ui/progress/ProgressDetail.kt` (Calendar, Calories, Estimated burn,
    Top foods, Macros, the weight ledger and the workout list).
- Modify:
  - `A/ui/theme/MivuTheme.kt`: `bandBitOff`, `bandOff`, `bandFarOff`,
    `tintBurn` and `tintFoods`, with light, dark and high-contrast values from
    `ios/Shared/MivuColors.swift` 30–34;
  - `A/pip/CompanionPresentation.kt`: new `CompanionPose`s;
  - `A/pip/CompanionRuntime.kt`: the `moment` mapping and
    `var showsProgressProps`;
  - `A/pip/PipRigScene.kt`: prop opacity and held joints;
  - `A/pip/PipGestures.kt`: `progressHeldArm`;
  - `A/ui/MivuApp.kt`: `composable<Route.Progress>` replaces `LaterUpdate()`,
    plus `Route.ProgressDetail(kind: String)`.
- Test:
  - `T/pip/PipRigSceneTest.kt` (additions);
  - `I/ui/progress/ProgressScreenTest.kt`.

**Interfaces:**
- Consumes: `progressRange(…, includeDailyReports = true)`, `topFoods`,
  `hasDays`, `weightHistory`, `workoutHistory`, `ProgressSnapshot` and the
  editor routes from Task 3.
- Produces:
  - `class ProgressViewModel(repository: DiaryRepository, profileID: UUID)`
    with:
    - `val range: StateFlow<ProgressRange>` and `fun select(range: ProgressRange)`;
    - `val state: StateFlow<ProgressUiState>` (`Loading`,
      `Loaded(snapshot, foods, progress)`, `Failed(message, last: Loaded?)`).
      It reloads on `repository.changes`, and the load holds `loadDays(range)`
      days ending today's waking date.
  - `enum class ProgressDetailKind { Calendar, Calories, Burn, TopFoods, Macros, Weight, Workouts }`.
  - `CompanionPose.PresentingCalm`, `PresentingCheer`, `ProgressEntrance`,
    `ProgressEntranceCheer`, `ProgressRange` and `ProgressTap`. They map to
    `PipMoment.Presenting(cheer)`, `ProgressEntrance(cheer)`, `ProgressRange`
    and `ProgressTap(level)`.
  - `CompanionRuntime.showsProgressProps: Boolean`. Setting it re-applies the
    current pose without animation, as iOS `didSet`.
- **Layout** (mockup frames 1–2; iOS `ProgressView.body`):
  - a segmented row Week · Month · 3M · Year, tagged `progressRange`;
  - an optional load-failure line with "Retry loading progress";
  - the headline card (`summary` surface, Pip at 150 dp, 120 dp at font
    scale ≥ 1.5);
  - "Weight": the weight card, which opens the weight ledger;
  - "Average day": the macros card, which opens Macros;
  - "More": the six rows, each 52 dp min, tagged `progressCalendar`,
    `progressCalories`, `progressBurn`, `progressTopFoods`, `openWorkouts` and
    `progressGoals`. Goals opens `Route.Goals`.
- **Pip:**
  - entrance once per visit (cheer if `headline.celebrates`), then
    `PresentingCheer` / `PresentingCalm`;
  - a range change plays `ProgressRange`;
  - each tap plays the next `ProgressTap` level;
  - Pip stops when the tab leaves;
  - under "Remove animations" the pose is still.
- **Detail screens:** the same chart at full width, scrolled horizontally by
  range windows; tap selects a value; a plain list below; "Earlier" pages
  until `hasDays(before:)` is false. Weight and workout ledgers page with
  `weightHistory` / `workoutHistory` and offer edit, delete and Ask Pip.
- **Charts:** Canvas only.
  - Every chart node has `contentDescription` set to the iOS chart summary.
  - A missing day is drawn as a dashed outline, never as 0.
  - Partial or pending days are drawn at 45% alpha with no band.

- [ ] **Step 1: Failing tests.**
  - `PipRigSceneTest`:
    - `progressPropsShowOnlyWhenEnabled`;
    - `heldArmPersistsThroughRest`.
  - `ProgressScreenTest` (synthetic 90-day fixture):
    - `everyRangeRendersHeadlineWeightAndMacros`;
    - `missingDayIsNoLogNotZero` (`missingDayCopy`);
    - `eachMoreRowOpensItsDetail`;
    - `goalsRowOpensTheGoalEditor`;
    - `weightLedgerPagesAndEdits`;
    - `notEnoughDataShowsTheCountdownPlaceholder` ("Weigh in on 2 more days
      to see your trend.");
    - `rangeSwitchKeepsTheLastReportOnFailure`;
    - `chartsHaveSpokenSummaries`;
    - `fontScale2StacksLegends`.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** those classes, `CompanionRuntimeTest` and `AppShellTest`.
  Expected: PASS.
- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/java/com/yakov103/mivu android/app/src/test/java/com/yakov103/mivu/pip android/app/src/androidTest/java/com/yakov103/mivu/ui/progress/ProgressScreenTest.kt
git commit -m "feat(android): add the chart-first Progress tab with Pip presenting"
```

### Task 5: Morning check-in, Settings "Your day" and the morning reminder

**Files:**
- Create:
  - `A/ui/today/MorningCheckIn.kt` (`MorningCheckInCard`, with a `compact`
    variant for Coach);
  - `A/day/MorningReminder.kt` (`MorningReminder`, `MorningReminderReceiver`);
  - `A/ui/settings/DaySettings.kt` (the "Your day" group).
- Modify:
  - `A/diary/DiaryQueries.kt` (`morningRecap`);
  - `A/ui/today/TodayViewModel.kt` and `TodayScreen.kt`;
  - `A/ui/coach/CoachScreen.kt` (the bubble above Pip, hidden while typing);
  - `A/ui/settings/SettingsScreen.kt`: "Your day"; "Setup" gains "Goals",
    plus "Redo setup with Pip" and "Backup & export" with their routes
    stubbed to Tasks 6–7;
  - `AndroidManifest.xml`: `POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED`, and
    the receiver with `exported="false"` and the four system actions.
- Test:
  - `T/day/MorningReminderTest.kt`;
  - `I/ui/today/MorningCheckInTest.kt`;
  - `I/day/MorningReminderReceiverTest.kt`.

**Interfaces:**
- Consumes: `recordWeight(startNewDay = false)`,
  `progressRange(endingOn, 7, true)` (`weight.changeFromSevenDaysAgoKg`,
  `latestWeight`), `DayCutoff` and `wakingDayTitle`.
- Produces:
  - `data class MorningRecap(val previous: DiaryDaySummary, val targetKcal: Double?)`;
  - `fun DiaryDatabase.morningRecap(activeDayID: UUID): MorningRecap?`. It
    finds the latest day before the active day's date (bounded, `LIMIT 1`),
    sums it with `diaryWeek`'s rules, and takes the goal on that date.
  - `TodayUiState.morning: MorningState?`, with
    `data class MorningState(val dayID: UUID, val greeting: String, val recap: MorningRecap?, val todayWeight: WeightEntry?, val asking: Boolean, val trendKg: Double?, val lastKg: Double?)`.
    It is shown when there is a recap, today has no meals, and
    `morningCardDismissedDay != dayID`. `asking` means no weight today and
    `morningWeightSkippedDay != dayID`.
  - `fun TodayViewModel.saveMorningWeight(kg: Double): Boolean`, rounding to
    0.1;
  - `skipMorningWeight()` and `dismissMorning()`;
  - `fun greeting(hour: Int): String`.
  - `object MorningReminder`:
    - `const val ENABLED = "morningReminder"` and `const val MINUTES = "morningReminderMinutes"`;
    - `fun nextTrigger(now: ZonedDateTime, minutes: Int): ZonedDateTime`,
      today at that time if it is still ahead, else tomorrow;
    - `fun schedule(context: Context)`;
    - `fun cancel(context: Context)`;
    - `fun post(context: Context)`: channel `"morning"` named "Morning
      check-in", `IMPORTANCE_DEFAULT`, notification ID 4, `setAutoCancel`, and
      a content intent to the launcher activity.
  - `class MorningReminderReceiver : BroadcastReceiver`. When enabled, it
    posts on the alarm action and then schedules; on the system actions it
    only schedules.
- **Card** (mockup frame 3):
  - a `Card` with the greeting as a heading;
  - a Close icon button labelled "Hide check-in";
  - the recap line and a `LinearProgressIndicator` labelled "Intake toward
    that day's goal";
  - an `OutlinedTextField` labelled "Weight in kilograms" or "Weight in
    pounds", whose placeholder is the last weight;
  - a trailing kg/lb dropdown;
  - "Skip" (outlined) and "Save" (filled), disabled until 20–400 kg;
  - the done line;
  - insert and remove with `AnimatedVisibility` (fade only under "Remove
    animations");
  - `HapticFeedbackType.Confirm` on save;
  - Pip on Today plays `Saved` through the existing companion event.
- **Coach bubble** (mockup frame 4): only while `asking`, hidden while typing.
  "Tell Coach instead" sets the draft to "My weight this morning is " and
  focuses the field.
- **Settings "Your day"** (mockup frame 11):
  - "Day starts at" is an `ExposedDropdownMenuBox` of 12 AM to 8 AM, using
    `DateFormat.getTimeFormat` hour labels;
  - "Morning check-in" is a `Switch`. On API 33+ it launches
    `RequestPermission(POST_NOTIFICATIONS)` first; below that it checks
    `areNotificationsEnabled()`;
  - "Reminder time" opens an M3 `TimePicker` dialog;
  - the footer is shown.

- [ ] **Step 1: Failing tests.**
  - `MorningReminderTest`:
    - `nextTriggerIsLaterTodayOrTomorrow`;
    - `nextTriggerSurvivesADstChange` (Europe/London, the last Sunday of
      October);
    - `greetingFollowsTheHour`.
  - `MorningCheckInTest`:
    - `cardAppearsAfterARolloverWithYesterdaysRecap` ("1,870" "of 2,100
      kcal");
    - `noRecapWhenYesterdayHasNoMeals`;
    - `skipCollapsesToTheDoneLine`;
    - `saveRecordsOnTheOpenDayAndShowsTheWeeklyTrend`;
    - `poundsAreSavedAsKilograms`;
    - `outOfRangeWeightCannotBeSaved`;
    - `firstMealHidesTheCard`;
    - `closeHidesItForThisDayOnly`;
    - `coachBubbleTellCoachFillsTheDraft`;
    - `dismissalIsSharedWithCoach`;
    - `dayStartsAtChangesTheFooterAndCutoff`.
  - `MorningReminderReceiverTest` (with `GrantPermissionRule` for
    `POST_NOTIFICATIONS`):
    - `turningOnSchedulesAndOffCancels`, checked by
      `PendingIntent.getBroadcast(…, FLAG_NO_CREATE)`;
    - `alarmPostsTheMorningNotification`: `activeNotifications` has ID 4 with
      the iOS title and body;
    - `bootReschedulesWithoutPosting`;
    - `disabledReceiverPostsNothing`.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement.** Put a one-line why at the `setWindow` call:
  "inexact by design: a reminder needs no exact-alarm permission."
- [ ] **Step 4: Run** those classes, then `TodayScreenTest`, `CoachScreenTest`
  and `ConnectionScreenTest`. Expected: PASS.
- [ ] **Step 5: Commit**

```bash
git add android/app/src/main android/app/src/test/java/com/yakov103/mivu/day android/app/src/androidTest/java/com/yakov103/mivu/day android/app/src/androidTest/java/com/yakov103/mivu/ui/today/MorningCheckInTest.kt
git commit -m "feat(android): add the morning check-in, day settings and reminder"
```

**Review batch 2** (Tasks 4–5) runs here.

### Task 6: Setup with Pip

**Files:**
- Create:
  - `A/onboarding/OnboardingTargets.kt` (`OnboardingAnswers`,
    `OnboardingTargets`);
  - `A/ui/onboarding/OnboardingScreen.kt` (the screen and
    `OnboardingViewModel`).
- Modify:
  - `A/diary/DiaryRepository.kt` (`Bootstrap.Ready.created`);
  - `A/connection/ChatGPTConnection.kt` (`inference()` takes
    `tools: JsonObject?`);
  - `A/coach/CoachWorker.kt` (call sites, if the type changes there);
  - `A/ui/MivuApp.kt` (`Route.Onboarding` as a full-screen `dialog<>`, opened
    once when `created`, and from Settings "Redo setup with Pip").
- Test:
  - `T/onboarding/OnboardingTargetsTest.kt`;
  - `I/ui/onboarding/OnboardingScreenTest.kt`.

**Interfaces:**
- Consumes:
  - `ChatGPTConnection.state`, `recordConsent`, `connect` and `inference()`;
  - `ChatGPTConnectButton`;
  - `updateProfile`, `recordWeight`, `goal(on, exact = true)` and `setGoals`
    (Task 2);
  - `PipCompanion` with `CompanionPose.Greeting`, `Attentive`, `Saved`,
    `Thinking` and `Recovery`.
- Produces:
  - `data class OnboardingAnswers(val about: ProfileAbout, val weightKg: Double, val targetKg: Double)`,
    with `keepsWeight`, `targetIsHealthy` and
    `fun estimate(year: Int = Year.now().value): NutritionValues`. These are
    iOS formulas, verbatim.
  - `object OnboardingTargets`:
    - `data class Reply(val targets: NutritionValues, val explanation: String)`;
    - `fun input(answers: OnboardingAnswers, estimate: NutritionValues, year: Int): List<CoachInferenceInput>`,
      with the iOS developer text verbatim and the user JSON with sorted keys;
    - `fun parse(text: String): Reply?`, accepting kcal 1200–5000, macro
      energy within 15%, and an explanation of 1–800 characters.
  - `Pace.kgPerWeek`: gentle 0.25, steady 0.5, faster 0.75.
  - `class OnboardingViewModel(repository, profileID, connection: ChatGPTConnection?, savedState: SavedStateHandle)`.
    Answers and step survive process death, and `save()` follows iOS `save()`:
    1. the stored profile, then `about`;
    2. the weight, only if it differs by ≥ 0.05 kg;
    3. today's exact goal, keeping its id and exercise credit.
- **Steps** (mockup row 2):
  - **Layout.**
    - A `LinearProgressIndicator` labelled "Setup progress", with the value
      "Step n of 6".
    - Back is an icon button. "Later" shows on hello. "Skip" shows on diet.
    - Pip sits at the top at 96 dp, or 170 dp on hello, and shrinks while the
      IME is visible.
    - The primary button is pinned above the IME (`imePadding`).
  - **About you.** Each row's unit is a dropdown. Height is cm or ft/in, and
    weight is kg or lb, stored metric. The IME action "Next" walks height →
    weight → birth year.
  - **Diet.** `FilterChip`s in a `FlowRow` with the nine iOS tags, plus the
    notes field.
  - **Connect.** It is skipped when `canInfer`. Otherwise:
    - it shows `ChatGPTConnectButton` (consent first);
    - "Waiting for ChatGPT…" shows while connecting;
    - the notice shows;
    - "Use the estimate instead" goes on to results.
  - **Results.**
    - The estimate shows at once with the badge "Estimate".
    - `askChatGPT` runs when `canInfer`:
      - Pip plays `Thinking` while it waits;
      - a parsed reply replaces the estimate, with "Tuned by ChatGPT" and
        Pip `Saved`;
      - a failure keeps the estimate, shows the footnote and "Try again", and
        Pip plays `Recovery`.
    - Every number is editable.
    - "Save my targets" saves.

- [ ] **Step 1: Failing tests.**
  - `OnboardingTargetsTest` ports iOS `OnboardingTargetsTests` with the same
    values:
    - `estimateLosesAtTheChosenPace` (1360 / 127 / 112 / 45);
    - `estimateKeepsWeightWithTheMidpointWhenSexIsSkipped` (2330);
    - `estimateNeverGoesBelowTheFloor` (1200);
    - `losingBelowAHealthyWeightIsNotATarget`;
    - `replyIsAcceptedOnlyWhenTheNumbersHoldTogether`.
  - `OnboardingScreenTest`, with a fake connection state and a fake inference
    returning synthetic JSON:
    - `newDiaryOpensSetupOnce`;
    - `existingDiaryNeverOpensSetup`;
    - `laterOpensTodayWithNoTargets`;
    - `unhealthyTargetBlocksContinue`;
    - `connectedSkipsTheConnectStep`;
    - `goodReplyShowsTunedTargets`;
    - `badReplyKeepsTheEstimate`;
    - `failedRequestOffersRetry`;
    - `saveWritesProfileWeightAndTodaysGoal`;
    - `redoFromSettingsIsPrefilled`;
    - `stepSurvivesActivityRecreation`;
    - `targetsAtLeast48dpAtFontScale2`.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** those classes, then `ChatGPTConnectionTest`,
  `CoachWorkerTest` and `AppShellTest`. Expected: PASS.
- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/java/com/yakov103/mivu android/app/src/test/java/com/yakov103/mivu/onboarding android/app/src/androidTest/java/com/yakov103/mivu/ui/onboarding
git commit -m "feat(android): add Pip-hosted setup that sets daily targets"
```

### Task 7: Reports, full suite, evidence and parity

**Files:**
- Create:
  - `A/report/DiaryReport.kt` (the model, CSV, `lastDays`, `shift`);
  - `A/report/DiaryReportPdf.kt` (`PdfDocument`, A4 at 595×842 pt, two
    passes for "Page n of N");
  - `A/ui/settings/BackupExportScreen.kt` ("Share a report");
  - `android/app/src/main/res/xml/report_paths.xml`;
  - `docs/verification/2026-10-24-android-progress-onboarding.md`;
  - `docs/verification/android-progress/*.png`.
- Modify:
  - `AndroidManifest.xml` (the `FileProvider`
    `${applicationId}.reports`);
  - `A/ui/MivuApp.kt` (`Route.BackupExport`);
  - `docs/parity.md`;
  - `docs/superpowers/plans/android-carried-items.md`.
- Test:
  - `T/report/DiaryReportTest.kt`;
  - `I/report/DiaryReportPdfTest.kt`;
  - `I/ui/settings/BackupExportScreenTest.kt`.

**Interfaces:**
- Consumes: `DiaryDatabase.snapshot()`, `goalOn`, `dayNutritionTotals`,
  `wakingDateLabel` and `DayCutoff`.
- Produces:
  - `class DiaryReport(snapshot: DiarySnapshot, from: String?, through: String?)`.
    Its fields `profileName`, `days`, `weights`, `from` and `through` are
    iOS's, and so are `mealsCSV`, `daysCSV`, `weightsCSV`, `calendarDayCount`
    and `fun number(value: Double?): String`.
  - `companion fun lastDays(count: Int, now: Instant, zone: String, cutoffHour: Int = DayCutoff.hour): Pair<String, String>`.
  - `fun DiaryReport.write(format: Format, directory: File): List<File>`, with
    the iOS file names "Mivu report <from> to <through>.pdf" and "Mivu
    meals|days|weights … .csv".
  - `enum class Format { PDF, CSV }`.
  - `fun DiaryReport.pdf(context: Context): ByteArray`. It draws the iOS
    layout with `Canvas` and `TextPaint`. The iOS Pip preview in the header is
    left out until the `app-icon` row adds Pip art to `res/`.
- **Screen** (mockup frame 12):
  - the range is an `ExposedDropdownMenuBox`; "Custom" opens
    `DateRangePickerDialog`;
  - the format is a segmented PDF | CSV;
  - the description line;
  - "Share report" is a tonal button showing "Preparing report" while busy;
  - the report is built on `Dispatchers.IO`, then
    `Intent.createChooser(ACTION_SEND or ACTION_SEND_MULTIPLE)` runs with
    `FLAG_GRANT_READ_URI_PERMISSION`;
  - the folder is deleted when the chooser result returns, or on the next
    open.

- [ ] **Step 1: Failing tests.**
  - `DiaryReportTest`:
    - `csvNeutralisesFormulasAndQuotes` (`=SUM(A1)` → `'=SUM(A1)`; `-5` stays
      `-5`; `a "b", c` → `"a ""b"", c"`);
    - `numbersUseAtMostOneDecimalAndNoGrouping`;
    - `lastDaysEndsOnTheWakingDay` (01:30, cutoff 4);
    - `allTimeUsesTheFirstAndLastDiaryDays`;
    - `legacyWeightWithoutADayUsesItsMeasuredDate`.
  - `DiaryReportPdfTest`:
    - `pdfHasPageCountFooterAndOpens` (parsed back with `PdfRenderer`; page
      count ≥ 1);
    - `emptyRangeStillMakesAReport`.
  - `BackupExportScreenTest`:
    - `shareLaunchesAChooserWithReadableUris`, with Espresso-Intents
      `intended(hasAction(ACTION_CHOOSER))` and the URI authority
      `…reports`;
    - `profileChangeDuringPreparationDropsTheFiles`.
- [ ] **Step 2: Run** them. Expected: FAIL. Then **implement** and run them
  again. Expected: PASS.
- [ ] **Step 3: Run the full suite once** at a clean commit:
  `./gradlew :app:testDebugUnitTest :app:connectedDebugAndroidTest :app:lintDebug :app:assembleRelease --rerun-tasks`,
  then `python3 scripts/ci/parity.py` and the `scripts/ci` unit tests.
  - Record the SHA, the emulator, and the counts from the JUnit XML.
  - Never count a skipped or zero-test class.
  - If a class fails, fix it, or record it honestly with its cause.
- [ ] **Step 4: Screenshots.**
  - Take them in light, dark and font scale 2.0, and compare them with the
    mockup.
  - The list: `progress-week`, `progress-month`, `progress-detail-calendar`,
    `today-morning`, `coach-weigh-in`, `onboarding-hello`, `onboarding-about`,
    `onboarding-results`, `weight-editor`, `goal-editor`, `settings-your-day`
    and `share-report`.
  - The reminder notification on the emulator is shown for layout only. Its
    delivery on a real phone is recorded as `blocked`.
- [ ] **Step 5: Parity.**
  - Android `done` with this record, where every test named passed:
    `progress`, `progress-chart-first`, `onboarding` and `day-rollover`.
  - `reports` Android `done`, if the PDF opens in a viewer from the share
    sheet on the emulator. Otherwise `partial`, with the reason.
  - `today`, `diary` and `pip`: update the notes, removing the M6 items.
  - `settings`: stays `partial`. Profiles, preferences and nutrition source
    remain.
- [ ] **Step 6: Carried items.**
  - Remove "Port the per-device day-cutoff setting" and "Add the morning
    check-in, the weight row and the goal editor", each with its outcome.
  - Add to Settings: "Backup & export: the archive export/import UI joins the
    report screen" (cross-reference Play readiness).
  - Add "Morning reminder: deliver and tap on a physical phone".
- [ ] **Step 7: Commit**

```bash
git add android/app/src/main android/app/src/test/java/com/yakov103/mivu/report android/app/src/androidTest/java/com/yakov103/mivu/report android/app/src/androidTest/java/com/yakov103/mivu/ui/settings/BackupExportScreenTest.kt docs/verification/2026-10-24-android-progress-onboarding.md docs/verification/android-progress docs/parity.md docs/superpowers/plans/android-carried-items.md
git commit -m "feat(android): share diary reports and record milestone 6"
```

**Final review** of the whole milestone runs here.
