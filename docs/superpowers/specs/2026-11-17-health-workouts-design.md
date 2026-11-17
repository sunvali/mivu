# Workouts from Apple Health (Garmin and other apps) — design

Status: draft for owner approval. iOS only.

## Intent

People who train with a Garmin watch should see those workouts in Mivu without
typing them, and the calories they burned should earn back food budget.

Mivu has no server, so it does not talk to Garmin directly. The Garmin Connect
iPhone app can share workouts, with calories, to Apple Health once the person turns
sharing on in Garmin Connect. Mivu reads them from Health. Apple Watch, Strava and
any other app that writes workouts to Health work the same way.

## Goals

- Import Health workouts, from any source app, into Mivu's existing workout store.
  Each shows its source app ("from Garmin Connect").
- Each imported workout's **active** calories count toward the existing exercise
  credit ("Exercise-adjusted remaining" on Today) when credit is on.
- Imports keep up on app open and through Health background delivery.
- Changes and deletions in Health or Garmin carry through to Mivu.

## Non-goals

- Writing anything to Health, including nutrition, weight or workouts.
- Garmin's own Health API, Connect IQ or any Garmin account.
- Android. `docs/parity.md` marks it pending, with Health Connect as the later
  route.
- Coach (OpenAI) seeing Health data. The owner said "not for now, maybe later".
- An onboarding step. The connect switch lives in Settings only.

## Anti-goals (a failure even if it works)

- Double credit: the same session counted twice, from two Health apps or from Health
  plus a workout told to Coach.
- Credit inflated by resting or all-day calories. Onboarding targets already assume
  light daily activity (×1.375).
- Any Health-sourced value reaching OpenAI or iCloud through Mivu.
- Past budgets the person already reviewed changing for no visible reason.
- A deleted workout coming back.

## Decisions (owner)

| # | Decision |
|---|----------|
| Source | Any app writing `HKWorkout` to Health; show the source app name. |
| Calories | Only the workout's active energy (`HKQuantityType(.activeEnergyBurned)` statistics on the workout). No basal, no all-day active energy. A workout with no active energy imports with **0 kcal** and a "No calories from Health" label; it must not hide the day's credit line. |
| Mixed day | The earn-back line uses the calories that are known and notes "N workouts without calories". This replaces today's all-or-nothing rule (`ProgressAnalytics.swift:54,64`, `DiaryDatabaseProgressQueries.swift:58`) for Today, Progress, the widget and Coach. Coach's own figures still leave out Health. |
| Widget | When credit is on, the widget and Live Activity add the credited burn to the target, matching Today. Background delivery republishes the snapshot. |
| Timing | Import on launch/foreground and through `HKObserverQuery` + background delivery. |
| Backfill | On first connect, import the last 7 local days plus today. |
| Late syncs | Afterwards, a Health workout that is new, changed or deleted affects only today and the 6 local days before it. Older days stay frozen: arrivals for them are ignored, and their imported copies are not updated or removed. |
| Empty days | Attach only to a `TrackingDay` that already exists for that local date (or today's active day). Skip dates Mivu has no day for, and never create days for imports. |
| Credit | The connect sheet includes "Add workout calories to my budget", switched on. Accepting turns on `exerciseCreditEnabled` from today onward, through the existing `set_goals` path. If today's goal started on an earlier date, that write creates a new goal record dated today, so past goals stay as they were (builder's call). |
| Editing | Imported workouts are read-only in Mivu; delete is allowed. A Mivu delete is permanent, and the workout is never re-imported. |
| Health changes | When the source changes or deletes a workout, Mivu updates or removes its copy, inside the late-sync window. |
| Overlap credit | Every Health workout in the window is imported. Credit counts one workout per group of workouts that overlap in time: a Health workout beats a Coach or manual one, and among Health workouts the earliest-imported wins. Nothing is skipped at import time, so if the winner is deleted, the next one counts again on its own. (Owner chose "count one only" and "Health one counts"; doing both at credit time is the builder's call.) |
| Coach overlap | Credit already leaves out the overlapped Coach or manual workout. In addition, show a local warning on Today and on the Coach receipt: "<Source app> may have this already. Remove yours?" with a one-tap remove. No OpenAI involvement. |
| Disconnect | When the person disconnects in Settings or revokes in iOS Settings, imported workouts stay and new imports stop. |
| Coach / OpenAI | Nothing Health-derived reaches Coach: no imported workouts, no Health burn in `DailyProgress`, no Health-inclusive "remaining". Today labels the Health part of the earn-back, so a lower number from Coach makes sense. |
| Backups | Folder backups leave out Health-sourced workouts (App Review 5.1.3: no health data in iCloud, and the folder may be iCloud Drive). After a restore, the 7-day backfill runs again. |
| Exports | User-initiated exports and reports **include** Health workouts, labeled with their source. |

## Approaches considered

- **A. Import into Mivu's workout store (chosen).** Health workouts become
  `WorkoutSession` rows marked as from Health. Today, Progress and exports see them
  with no new data path. Costs: duplicate, deletion and filtering rules.
- **B. Live Health total, nothing stored.** Smaller, but past days aren't stable and
  history never sees the workouts. Rejected.
- **C. Garmin Health API.** Needs a Mivu server and Garmin partner approval, which
  goes against "no Mivu server". Rejected.

## How it fits today's code

- `WorkoutSession` / `WorkoutBurnSource` (`ios/Mivu/Diary/DiaryModels.swift`). Add a
  `health` burn source, plus the Health workout UUID and source app name. Old rows
  must decode unchanged.
- `ProgressAnalytics.daily` (`ios/Mivu/Progress/ProgressAnalytics.swift`) already
  adds burn to remaining when credit is on. Health workouts count with known kcal
  (0 when Health has none), so they never turn the day's burn into `nil`.
- `createWorkout` / `saveWorkout` and the workout tombstone table
  (`ios/Mivu/Diary/DiaryDatabaseProgress.swift`). The import goes through the same
  validated, owned operations (roadmap §6: no second store). A tombstone for a deleted
  Health workout must also stop that Health UUID from being re-imported.
- Coach reaches workouts through `context.workouts`, `coachWorkout(id:)`,
  `CoachProgress.daily/dailyReports` and `CoachReplyLines.factLine`
  (`ios/Mivu/Diary/DiaryDatabaseCoachContext.swift`, `ios/Mivu/Coach/`). Every one
  of these must leave out Health rows and Health burn. Coach tools must also refuse
  to edit or delete a Health workout by ID.
- Folder backup writes a `DiarySnapshot` (`ios/Mivu/Diary/FolderBackup.swift`). Filter
  out Health workouts there. On restore, don't delete Health workouts already on the
  device just because the backup lacks them. Keep the Health-UUID tombstones in the
  backup so a restore doesn't bring back hidden workouts.
- Today's credit line (`ios/Mivu/Diary/TodayView.swift`, `todayGoalSummary`) gains the
  Health share and the overlap warning.
- The widget (`ios/Mivu/WidgetSnapshotWriter.swift`) and Live Activity show eaten
  versus target today. `WidgetSnapshot` gains the credited burn, or an adjusted
  target, so they match Today.

## Platform and review constraints

- Add the HealthKit capability and background-delivery entitlement, plus an
  `NSHealthShareUsageDescription` in English. There is no update (write)
  description, because Mivu only reads.
- Read types: `HKObjectType.workoutType()` and `activeEnergyBurned`.
- iOS doesn't say whether read access was denied, so treat "no workouts" and
  "denied" the same way, and point to iOS Settings › Health › Mivu.
- Update the privacy manifest, App Store privacy answers and the privacy text in
  `docs/development/app-store-submission.md`: Health data is read and stays on
  the device, apart from exports the person chooses to make.
- Keep the `OpenAIConsent` text as it is. Health data isn't shared, so the consent
  doesn't widen.

## Verification

- Unit tests with synthetic workouts behind a small protocol seam:
  - Import, dedupe, updates and deletions.
  - Overlap credit (one per overlapping group, Health wins) and 0-kcal and mixed-day handling.
  - The 7-day late-sync window freezing older days.
  - Skipping days that don't exist, and the 7-day window.
  - Tombstones blocking re-import.
  - Health rows filtered out of Coach context and backups, and kept in exports.
- Smoke test for the Settings connect flow and the Today label, following
  AGENTS.md test-proportionality.
- Physical phone (owner, real Garmin): a Garmin activity reaches Mivu through Health
  with the same active calories Garmin Connect shows, and the budget rises. Delete
  in Garmin and it disappears from Mivu. Check background delivery after a workout.
  Stays `blocked` until the owner runs it.
- `docs/parity.md`: iOS done, Android pending (Health Connect).

## Left to the builder

- Mapping `HKWorkoutActivityType` onto `strength` / `cardio` / `other`.
- Where the Health anchor and connected state live. Use device-local storage, never
  the backup.
- The overlap rule's exact threshold (any time overlap is fine to start).
- Copy and layout of the Settings row and connect sheet, following HIG, Dynamic
  Type, VoiceOver and 44-point targets.

## Builder's calls already made

- The connect switch lives in Settings only. Mivu only reads from Health. Android is
  pending in `docs/parity.md`.
- Overlap is resolved when credit is counted, not at import (see Overlap credit).
- Turning on credit creates a goal dated today when needed (see Credit).
- A late-sync window of 7 local days is measured from the device's current local
  date.
