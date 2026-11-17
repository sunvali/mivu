# Workouts from Apple Health Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Import workouts from Apple Health (Garmin Connect and any other source)
into Mivu's workout store. Their active calories earn back food budget when
exercise credit is on.

**Architecture:** Each imported workout is an ordinary `WorkoutSession` whose `id`
is the `HKWorkout.uuid`, with `burnSource = .health`. Because the ID is reused, the
existing workout tombstones and `deletedWorkoutIDs` already stop a deleted workout
from being re-imported, including across a backup restore. One pure function,
`ExerciseCredit.daily`, replaces today's all-or-nothing burn sum everywhere. Coach
queries and folder backups filter out `.health` rows. A thin
HealthKit reader passes changes to a single validated store operation.

**Tech Stack:** Swift, SwiftUI, HealthKit (`HKAnchoredObjectQuery`,
`HKObserverQuery`, background delivery), SQLite (existing), Swift Testing.

**Spec:** `docs/superpowers/specs/2026-11-17-health-workouts-design.md`

## Changes made during implementation

- **Widget:** there's no `WidgetSnapshot.earnedKcal`. `DailyProgress.creditedKcalTarget`
  (the target plus credited burn when credit is on) feeds both the widget and the
  Live Activity target, so the widget code doesn't change.
- **Sync:** `changes(since:anchor:)` returns the full window of workouts every time,
  plus deletions since the anchor. A restored or reinstalled diary gets its recent
  workouts back without resetting the anchor.
- **No calories:** a Health workout with no active energy is stored with nil kcal,
  not 0. It counts in `uncountedWorkoutCount`, and the earn-back line still shows,
  as the spec requires.
- **Reading workouts:** Coach reads through `coachWorkout`, which refuses Health
  rows. The workout screen uses the new `DiaryStore.workout(id:expectedProfileID:)`.
  Progress rows for Health workouts offer no Ask Pip.
- **Exercise credit:** `DiaryStore.enableExerciseCredit(from:expectedProfileID:)`
  turns credit on from today.

## Global Constraints

- iOS only. Read-only HealthKit types: `HKObjectType.workoutType()` and
  `HKQuantityType(.activeEnergyBurned)`. Mivu never writes to Health.
- Count only a workout's **active** energy. No basal energy, and no all-day active
  energy samples.
- Import window: today plus the 6 local days before it, counted in the profile time
  zone. Use the same window for the first backfill and for later changes. Older days
  are never touched.
- Attach workouts only to a `TrackingDay` that already exists. Never create days
  during an import.
- Nothing from Health reaches Coach or OpenAI: no `.health` rows, no Health burn, no
  Health-inclusive remaining. Leave the `OpenAIConsent` text unchanged.
- Folder backups leave out `.health` workouts but keep `deletedWorkoutIDs`.
  User-initiated exports and reports include them.
- Copy is English only. Support Dynamic Type and VoiceOver, with targets of at least
  44 points.
- Tests use synthetic data only. Run them with XcodeBuildMCP on a reserved simulator
  with a checkout-specific DerivedData directory, as AGENTS.md requires. Use suite
  selectors, and never count zero tests as passing.
- PRs touching `ios/` update `docs/parity.md`.

## Review Focus

1. **Coach workout logged without a time.** "Ran this morning" is saved as
   `.dateOnly`, so it can't overlap by clock time. Expected: it counts as overlapping
   a Health workout of the same `kind` on the same day, and credits only the Health
   one. The test is in Task 2.
2. **The same Health workout delivered twice** (HealthKit re-delivers it, or the app
   relaunches). Expected: the store is unchanged and `revision` is not bumped. The
   test is in Task 3.
3. **A workout recorded in another time zone or crossing midnight.** Expected: its
   date comes from `performedAt = startDate` in the **profile** time zone, it attaches
   to an existing day with that `localDate` in any zone, and it is skipped if there is
   none. The test is in Task 3.
4. **Duration out of range** (a 20-second auto-detected walk, or a 30-hour hike).
   Expected: duration is clamped to `1...1440` minutes, so validation never rejects
   the whole batch. The test is in Task 3.
5. **Restore from a backup, then sync.** Expected: a deleted Health workout stays
   deleted, because its ID is in `deletedWorkoutIDs`, and the window re-imports the
   rest. The test is in Task 5.

---

### Task 1: Health-sourced workout fields

**Files:**
- Modify: `ios/Mivu/Diary/DiaryModels.swift:173` (`WorkoutBurnSource`), `:193-204` (`WorkoutSession`), `:491` (`validateWorkoutFields`)
- Test: `ios/MivuTests/HealthWorkoutTests.swift` (create)

**Interfaces:**
- Produces: `WorkoutBurnSource.health`, `WorkoutSession.healthSource: String?`
  (the source app's display name), and
  `extension WorkoutSession { var isFromHealth: Bool }`.

- [x] **Step 1: Write failing tests** in `@Suite struct HealthWorkoutTests`:
  - `oldWorkoutPayloadDecodesWithoutHealthSource`: decoding a `WorkoutSession` JSON
    with no `healthSource` gives `healthSource == nil` and `isFromHealth == false`.
  - `healthWorkoutRequiresSourceName`: `validateWorkoutFields` throws
    `DiaryError.invalidData` for `.health` with a nil or empty `healthSource`, for a
    non-health session with a `healthSource`, and for a name over 100 characters.
    It passes for `.health` with `"Garmin Connect"`.
- [ ] **Step 2: Run** `MivuTests/HealthWorkoutTests`. Expected: FAIL (no `.health` case).
- [x] **Step 3: Implement** the new case and field (synthesized `Codable` decodes a
  missing optional as nil), `isFromHealth` (`burnSource == .health`), and the
  validation rule.
- [x] **Step 4: Run** `MivuTests/HealthWorkoutTests` plus `MivuTests/DiaryTests`
  (snapshot validation callers). Expected: PASS.
- [x] **Step 5: Commit** `feat(health): mark workouts imported from Apple Health`

### Task 2: Exercise credit rule (overlap and known part)

**Files:**
- Create: `ios/Mivu/Progress/ExerciseCredit.swift`
- Modify: `ios/Mivu/Progress/ProgressAnalytics.swift:6-16` (`DailyProgress`), `:53-68`, `:79-97`
- Modify: `ios/Mivu/Diary/DiaryDatabaseProgressQueries.swift:35-73` (`progressRange`)
- Modify: `ios/Mivu/Diary/DiaryStore.swift:568` (`coachProgress`), `:738` (`progressForDisplay`)
- Test: `ios/MivuTests/ProgressAnalyticsTests.swift`, `ios/MivuTests/ProgressStoreTests.swift`

**Interfaces:**
- Consumes: `WorkoutSession.isFromHealth` (Task 1).
- Produces:
  ```swift
  struct ExerciseCredit: Equatable, Sendable {
      let creditedKcal: Double        // sum of counted workouts' known kcal
      let healthKcal: Double          // part of creditedKcal from Health workouts
      let uncountedCount: Int         // counted workouts with nil kcal
      let overlapped: [UUID]          // non-Health workouts left out because a Health one overlaps
      static func daily(_ workouts: [WorkoutSession]) -> ExerciseCredit
  }
  ```
  - `DailyProgress` gains `uncountedWorkoutCount: Int` and `healthBurnKcal: Double?`
    (nil when there are no Health workouts). `estimatedBurnKcal` becomes
    `creditedKcal`, and nil only when the day has no workouts.
  - `progressRange(..., includeHealth: Bool, ...)`: `coachProgress` passes `false` and
    `progressForDisplay` passes `true`.

Overlap rule (not fixed by the signature):
- Interval = `[performedAt, performedAt + durationMinutes·60)`.
- Two workouts overlap if both are `.exact` and their intervals intersect, or if one
  is `.dateOnly` and the other has the same `kind` (same day, since `daily` gets one
  day's workouts).
- Within each overlapping group, count one: a Health workout before a non-Health one,
  then the lowest `ordinal`/earliest `performedAt`, then `id`.

- [x] **Step 1: Write failing tests** in `ProgressAnalyticsTests`:
  - `creditCountsKnownPartAndNotesUnknown`: Health 400 kcal plus a Coach workout with
    nil kcal, with credit on, gives `estimatedBurnKcal == 400`,
    `uncountedWorkoutCount == 1` and adjusted remaining = remaining + 400.
  - `overlappingHealthWorkoutsCountOnce`: Garmin 400 at 07:00–07:45 and Apple Watch
    380 at 07:05–07:40 give credited 400 and `healthBurnKcal == 400`.
  - `healthBeatsOverlappingCoachWorkout`: Coach cardio `.exact` 07:00, 30 min,
    300 kcal, plus Health cardio 07:10 at 400 gives credited 400 and `overlapped`
    containing the Coach ID.
  - `dateOnlyCoachWorkoutOverlapsSameKindHealth` (Review Focus 1): Coach cardio
    `.dateOnly` 250, Health cardio 400 and Health strength 100 give credited 500.
  - `deletingWinnerLetsRunnerUpCount`: drop the Garmin row from the previous fixture
    and the Apple Watch 380 is credited.
- [x] **Step 2: Write failing test** in `ProgressStoreTests`:
  `coachProgressExcludesHealthWorkouts`. A day has one Coach workout (200) and one
  imported `.health` workout (400), with credit on.
  - `coachProgress(...).daily` has `workoutCount == 1`, `estimatedBurnKcal == 200`
    and `healthBurnKcal == nil`, and `workouts` doesn't contain the Health ID.
  - `progressForDisplay` has `workoutCount == 2` and `estimatedBurnKcal == 600`.
  - Insert the Health row with `transaction.saveWorkout` until Task 3 lands.
- [ ] **Step 3: Run** `MivuTests/ProgressAnalyticsTests` and `MivuTests/ProgressStoreTests`. Expected: the new tests FAIL.
- [x] **Step 4: Implement**
  - Add `ExerciseCredit.daily`.
  - Route both `ProgressAnalytics.daily(readModel:)` and `daily(snapshot:localDate:)`
    through it, and add the `DailyProgress` fields.
  - In `progressRange`, replace the SQL `SUM` burn with decoding that day's `workout`
    rows into `ExerciseCredit.daily`. Drop `.health` rows from both the credit and the
    `WorkoutReference` list when `includeHealth` is false.
  - Update existing assertions that expected nil burn for a day with unknown calories.
    This is the intended rule change (spec "Mixed day").
- [ ] **Step 5: Run** the same two suites plus `MivuTests/ProgressInsightsTests` and `MivuTests/CoachReplyLinesTests`. Expected: PASS.
- [x] **Step 6: Commit** `feat(progress): credit known workout calories once per overlap`

### Task 3: Store operation that applies Health changes

**Files:**
- Create: `ios/Mivu/Diary/DiaryDatabaseHealth.swift`
- Modify: `ios/Mivu/Diary/DiaryStore.swift` (public wrapper next to `deleteWorkout`, around `:449`)
- Test: `ios/MivuTests/HealthWorkoutStoreTests.swift` (create)

**Interfaces:**
- Consumes: Task 1 fields, `DiaryTransaction.saveWorkout`/`deleteWorkout(id:revision:)`
  (`DiaryDatabaseProgress.swift:62,117`), `ProgressAnalytics.window(endingOn:days:offset:zone:)`.
- Produces:
  ```swift
  struct HealthWorkout: Equatable, Sendable {
      let id: UUID; let start: Date; let end: Date
      let activeKcal: Double?; let sourceName: String; let kind: WorkoutKind
  }
  // DiaryStore
  func applyHealthWorkouts(_ upserts: [HealthWorkout], deletedIDs: [UUID], now: Date, expectedProfileID: UUID) throws
  ```

Rules:
- `localDate = diaryDateLabel(start, zone: profile.timeZoneID)`. Skip the workout if
  the date is outside the 7-label window ending today.
- Find the day with `SELECT … FROM day WHERE localDate = ?`, preferring one in the
  profile zone. Skip if there is none. Don't use `resolveDay`, because it creates
  days.
- Skip silently when the ID is in `workout_tombstone`.
- Map to `WorkoutSession(id: h.id, performedAt: h.start, timePrecision: .exact,
  durationMinutes: clamp(round((end-start)/60), 1...1440), exercises: [],
  estimatedBurnKcal: h.activeKcal, burnSource: .health, healthSource: h.sourceName)`.
  Insert it with revision 1. If a row already exists, bump the revision only when a
  field differs.
- `deletedIDs`: delete the existing `.health` row, which tombstones it, only when its
  day's `localDate` is in the window. Ignore unknown IDs and non-Health IDs.
- Everything happens in one `pagedMutation` transaction, so a single invalid
  workout skips only that workout and doesn't fail the batch.

- [x] **Step 1: Write failing tests** (fixture as in `ProgressStoreTests`: zone
  `Asia/Jerusalem`, a store with injected `currentTime`):
  - `importsIntoExistingDayWithinWindow`: one day exists for today. A Health workout
    at 07:00 for 45 min with 412 kcal from "Garmin Connect" gives one `.health`
    workout with `durationMinutes == 45`, `estimatedBurnKcal == 412` and
    `id == h.id`.
  - `skipsDatesWithoutDayAndOutsideWindow`: workouts dated 3 days ago (no day there)
    and 8 days ago (a day exists) both import nothing, and no day is created.
  - `reapplyIsIdempotent` (Review Focus 2): applying the same batch twice leaves
    `revision == 1` and an unchanged `snapshotForExport()`.
  - `changeUpdatesAndDeleteTombstones`: kcal changed from 412 to 430 gives
    `revision == 2`. Then `deletedIDs: [h.id]` removes it, and applying the upsert
    again doesn't bring it back.
  - `userDeleteBlocksReimport`: `deleteWorkout(id:)` from Mivu, then applying the same
    upsert again, leaves no workout.
  - `profileZoneDecidesDate` (Review Focus 3): a start at 23:30 UTC, which is the next
    day in Jerusalem, attaches to the Jerusalem next-day day.
  - `durationIsClamped` (Review Focus 4): a 20-second workout gives `1` and a 30-hour
    one gives `1440`.
  - `staleWindowChangesIgnored`: a Health row dated 8 days ago (seeded by
    `saveWorkout`) is not updated or deleted.
- [ ] **Step 2: Run** `MivuTests/HealthWorkoutStoreTests`. Expected: FAIL (no `applyHealthWorkouts`).
- [x] **Step 3: Implement** `DiaryTransaction.applyHealthWorkouts` in the new file and
  the `DiaryStore` wrapper.
- [x] **Step 4: Run** `MivuTests/HealthWorkoutStoreTests` and `MivuTests/ProgressStoreTests`. Expected: PASS.
- [x] **Step 5: Commit** `feat(health): apply Apple Health workout changes to the diary`

### Task 4: Keep Health out of Coach

**Files:**
- Modify: `ios/Mivu/Diary/DiaryStore.swift:559` (`coachWorkout`)
- Modify: `ios/Mivu/Diary/DiaryDatabaseCoachContext.swift:254-256` (workout source lookup), `:261-275` (`progressRangeInsideContext` query)
- Test: `ios/MivuTests/CoachStoreTests.swift`

**Interfaces:**
- Consumes: `WorkoutSession.isFromHealth`, `applyHealthWorkouts` (Task 3).
- Produces: none. Coach behavior stays the same for non-Health rows.

- [x] **Step 1: Write failing test** `coachNeverSeesHealthWorkouts`: import one Health
  workout and log one Coach workout on today's day.
  - `coachWorkout(id: healthID)` throws `DiaryError.notFound`.
  - The Coach context's `workouts` holds only the Coach workout's ID.
  - `coachJSON` of the context and of `coachProgress` contains neither the Health
    UUID string nor `"Garmin Connect"`.
- [ ] **Step 2: Run** `MivuTests/CoachStoreTests`. Expected: FAIL.
- [x] **Step 3: Implement**
  - `coachWorkout` throws `.notFound` for `.health`.
  - The context SQL adds `AND COALESCE(json_extract(CAST(w.payload AS TEXT), '$.burnSource'), '') <> 'health'`.
  - The `.workout(id)` source lookup leaves Health rows out.
  - Coach edit and delete tools already require a workout Coach knows about
    (`CoachTools.swift:200`), so they can't target a Health ID.
- [ ] **Step 4: Run** `MivuTests/CoachStoreTests`, `MivuTests/CoachEngineTests` and `MivuTests/CoachIndexedContextTests`. Expected: PASS.
- [x] **Step 5: Commit** `feat(coach): keep Apple Health workouts out of Coach`

### Task 5: Folder backups leave out Health workouts

**Files:**
- Modify: `ios/Mivu/Diary/FolderBackup.swift:244-288` (both `save` paths)
- Modify: `ios/Mivu/Diary/DiaryModels.swift` (snapshot extension)
- Test: `ios/MivuTests/ArchiveTests.swift`

**Interfaces:**
- Produces: `extension DiarySnapshot { func withoutHealthWorkouts() -> DiarySnapshot }`,
  which drops `.health` workouts and keeps `deletedWorkoutIDs`.

- [x] **Step 1: Write failing tests:**
  - `backupOmitsHealthWorkoutsButKeepsTombstones`: save to a temp backup folder. The
    archive read back contains the Coach workout, not the Health one, and still lists
    a previously deleted Health ID in `deletedWorkoutIDs`.
  - `exportKeepsHealthWorkouts`: `snapshotForExport()` still contains the Health
    workout.
  - `restoreThenSyncKeepsDeletedHidden` (Review Focus 5): restore from that backup,
    then `applyHealthWorkouts` with the deleted ID and one live ID. Only the live one
    is present.
- [ ] **Step 2: Run** `MivuTests/ArchiveTests`. Expected: FAIL.
- [x] **Step 3: Implement**
  - `save(_ snapshot:)` encodes `snapshot.withoutHealthWorkouts()`.
  - `save(_ request:coordinator:)` re-encodes `archive.snapshot.withoutHealthWorkouts()`
    with `DiaryArchive.encode` before `write`. Pass that same filtered snapshot to
    `beginSave` and `write`.
- [x] **Step 4: Run** `MivuTests/ArchiveTests` and `MivuTests/DiaryExportConcurrencyTests`. Expected: PASS.
- [x] **Step 5: Commit** `feat(backup): leave Apple Health workouts out of folder backups`

### Task 6: HealthKit reader and sync

**Files:**
- Create: `ios/Mivu/Health/HealthWorkoutSync.swift`
- Modify: `ios/Config/Mivu.entitlements` (`com.apple.developer.healthkit` = true, `com.apple.developer.healthkit.background-delivery` = true)
- Modify: `ios/Config/Info.plist` (`NSHealthShareUsageDescription`)
- Modify: `ios/Mivu/MivuApp.swift` (start sync at launch; trigger on `scenePhase == .active`)
- Test: `ios/MivuTests/HealthWorkoutSyncTests.swift` (create)

**Interfaces:**
- Consumes: `DiaryStore.applyHealthWorkouts` (Task 3), `publishWidgetSnapshot` (`WidgetSnapshotWriter.swift`).
- Produces:
  ```swift
  protocol HealthWorkoutReading: Sendable {
      func requestAuthorization() async throws
      /// Changes since `anchor` (nil = everything since `since`).
      func changes(since: Date, anchor: Data?) async throws -> (upserts: [HealthWorkout], deletedIDs: [UUID], anchor: Data?)
  }
  @MainActor @Observable final class HealthWorkoutSync {
      var isConnected: Bool                       // device-local, UserDefaults key "health.connected.<profileID>"
      init(reader: HealthWorkoutReading, model: DiaryViewModel, defaults: UserDefaults)
      func connect() async throws                 // authorization, then sync()
      func disconnect()                           // stop observing; clear anchor; keep imported rows
      func sync() async                           // changes → applyHealthWorkouts → model.refresh → publishWidgetSnapshot
      func startObserving()                       // HKObserverQuery + enableBackgroundDelivery(.immediate); calls sync(), then completion handler
  }
  static func workoutKind(_ type: HKWorkoutActivityType) -> WorkoutKind
  ```
- `HKHealthReader: HealthWorkoutReading` uses `HKAnchoredObjectQuery` on
  `HKObjectType.workoutType()`, predicated on `startDate >= since`.
  - `activeKcal` = `workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())`.
  - `sourceName` = `workout.sourceRevision.source.name`.
- Store the anchor in UserDefaults under `"health.anchor.<profileID>"`, never in the
  diary or backup. A missing anchor means a backfill with
  `since` = the start of the window's first day.
- Mapping (builder's call): `.traditionalStrengthTraining`,
  `.functionalStrengthTraining`, `.coreTraining` and `.crossTraining` become
  `.strength`. Running, walking, cycling, swimming, rowing, elliptical,
  stair climbing, HIIT and hiking become `.cardio`. Everything else is `.other`.
- `NSHealthShareUsageDescription`: "Mivu reads your workouts from Apple Health, such
  as those from Garmin Connect or Apple Watch, so their active calories can add to
  your daily food budget. They stay on this iPhone."

- [x] **Step 1: Write failing tests** with a fake `HealthWorkoutReading`:
  - `syncAppliesChangesAndStoresAnchor`: the first sync passes `anchor: nil`, applies
    one workout and stores the anchor. The second passes that anchor back.
  - `disconnectKeepsWorkoutsAndStopsImports`: after `disconnect()`, a `sync()` makes no
    reader call and the imported workout remains.
  - `workoutKindMapping`: running gives `.cardio`, traditional strength gives
    `.strength` and yoga gives `.other`.
- [ ] **Step 2: Run** `MivuTests/HealthWorkoutSyncTests`. Expected: FAIL.
- [x] **Step 3: Implement** the sync, `HKHealthReader`, entitlements, the plist string and the launch/foreground hooks.
  - Skip the sync when `DiaryLaunch.isUITest` is set.
  - The observer's completion handler must always be called.
- [x] **Step 4: Run** `MivuTests/HealthWorkoutSyncTests` and `MivuTests/MivuServicesTests`. Expected: PASS. Build the `Mivu` scheme for the simulator. Expected: success.
- [x] **Step 5: Commit** `feat(health): read workouts from Apple Health`

### Task 7: Settings, Today, workout detail and widget

**Files:**
- Create: `ios/Mivu/Health/HealthSettingsSection.swift`
- Modify: `ios/Mivu/Diary/SettingsView.swift` (new `Section("Apple Health")` after "Diary preferences", around `:171-197`)
- Modify: `ios/Mivu/Diary/TodayView.swift:889-892` (credit line)
- Modify: `ios/Mivu/Progress/ProgressView.swift:518-575` (`WorkoutDetailView`)
- Modify: `ios/Shared/WidgetSnapshot.swift`, `ios/Mivu/WidgetSnapshotWriter.swift:13-15`, `ios/Mivu/DayProgressActivity.swift`
- Test: `ios/MivuTests/WidgetSnapshotTests.swift`, `ios/MivuTests/HealthWorkoutTests.swift`; smoke

**Interfaces:**
- Consumes: `HealthWorkoutSync` (Task 6), `ExerciseCredit` / `DailyProgress.healthBurnKcal`, `uncountedWorkoutCount` (Task 2).
- Produces: `WidgetSnapshot.earnedKcal: Double?`. Decode it with `decodeIfPresent` so
  an old snapshot file still reads. The widget target is `target + earnedKcal`.
  Set `earnedKcal` only when credit is on.

UI copy (fixed):
- Settings row: a toggle labeled "Read workouts from Apple Health", with the footer
  "Workouts from Garmin Connect, Apple Watch and other apps that share with Health.
  They stay on this iPhone and are not shared with Coach."
- Connect sheet: the title "Apply workout calories to your budget?", a toggle labeled
  "Add workout calories to my budget" (on by default), and the button "Connect". On
  Connect, call `connect()`. If the toggle is on, set `exerciseCreditEnabled` with the
  existing goal write; `setGoals` with today's `effectiveLocalDate` creates a goal
  dated today when the current one started earlier.
- When nothing imports, show a footer hint: "No workouts yet? In Garmin Connect, turn
  on Apple Health sharing; in iOS Settings › Health › Data Access, allow Mivu."
- Today credit line: "Exercise-adjusted remaining: N kcal", followed by
  "Includes M kcal from Apple Health" when `healthBurnKcal > 0` and "K workouts
  without calories" when `uncountedWorkoutCount > 0`.
- Overlap warning. Show it on Today under the credit line for each
  `ExerciseCredit.overlapped` ID, and in `WorkoutDetailView` for an overlapped
  workout. (The Coach receipt's workout link opens `WorkoutDetailView`, so this is
  how the receipt surfaces it; builder's call.) The text is "<source> may have this
  workout already. Remove yours?", with a "Remove" button that calls the existing
  `deleteWorkout`.
- `WorkoutDetailView` for `isFromHealth`:
  - Show "From <healthSource>", and "No calories from Health" when kcal is nil.
  - Hide "Edit workout" and keep "Delete workout".
  - The delete confirmation adds: "It won't be imported again."

- [x] **Step 1: Write failing tests:**
  - `WidgetSnapshotTests.earnedCaloriesRaiseTarget`: credit on with Health at 400 kcal
    gives `earnedKcal == 400`. Credit off gives nil. An old JSON without the key
    decodes.
  - `HealthWorkoutTests.detailHidesEditForHealth`: a presentation helper
    `WorkoutDetailPresentation(session:).canEdit == false` and
    `.sourceLine == "From Garmin Connect"`.
- [ ] **Step 2: Run** `MivuTests/WidgetSnapshotTests` and `MivuTests/HealthWorkoutTests`. Expected: FAIL.
- [x] **Step 3: Implement** the views and the widget field, keeping 44-point targets
  and accessibility identifiers `healthSettingsToggle`, `todayHealthCredit` and
  `workoutOverlapRemove`.
- [x] **Step 4: Run** the two suites plus `MivuTests/DayProgressActivityTests`.
  Expected: PASS. Then `python3 scripts/ci/smoke.py --simulator-id <reserved-UUID>`.
  Expected: PASS within 120 s.
- [x] **Step 5: Commit** `feat(health): connect Apple Health and show earned workout calories`

### Task 8: Docs and device verification record

**Files:**
- Modify: `docs/parity.md` (new row `health-workouts`: iOS `partial` until device check, Android `pending`, note "Android: Health Connect later")
- Modify: `docs/development/app-store-submission.md` (HealthKit read-only; Health data stays on device and is excluded from backups and Coach; guideline 5.1.3)
- Create: `docs/verification/2026-11-17-health-workouts.md`
- Modify: `README.md` "What you get" (one bullet: workouts from Apple Health, including Garmin)

- [x] **Step 1:** Write the verification record.
  - Record the source SHA, the simulator and OS, and every suite from Tasks 1–7 with
    its result counts, plus the smoke result.
  - Add the physical-phone checklist marked `blocked`, pending the owner's real
    Garmin:
    1. A Garmin activity appears with the same active kcal Garmin Connect shows, and
       the budget rises.
    2. It appears after a workout without opening Mivu, through background delivery
       and the widget.
    3. Deleting it in Garmin removes it from Mivu.
    4. Deleting it in Mivu doesn't bring it back.
    5. Wearing an Apple Watch and a Garmin on the same session credits it once.
- [x] **Step 2:** Update parity and the App Store doc. Run `python3 scripts/ci/` checks for parity and docs, if present.
- [x] **Step 3: Commit** `docs(health): record Apple Health workouts verification and parity`
