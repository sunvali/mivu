# Workouts from Apple Health — verification

- Branch: `feat/health-workouts`. Base: `main` @ `720cc3f`.
- Spec: `docs/superpowers/specs/2026-11-17-health-workouts-design.md`
- Plan: `docs/superpowers/plans/2026-11-17-health-workouts.md`
- Environment so far: Linux, with no Swift toolchain or Xcode. The code was written
  and checked by reading only. **Nothing here has been built or run yet.**

## Results

Every native check is `blocked` until the owner's Mac is back. Run them with
XcodeBuildMCP on a reserved simulator, with a checkout-specific DerivedData. Then
record the tested SHA and the result counts here. A suite that runs zero tests
does not count.

| Run | Scope | Result |
|---|---|---|
| Build | `Mivu` scheme, Debug, iOS simulator | blocked (no Mac) |
| Model | `MivuTests/HealthWorkoutTests` | blocked |
| Credit rule | `MivuTests/ProgressAnalyticsTests` | blocked |
| Store import | `MivuTests/HealthWorkoutStoreTests` | blocked |
| Coach privacy | `MivuTests/CoachStoreTests` (incl. `coachNeverSeesHealthWorkouts`) | blocked |
| Backup | `MivuTests/ArchiveTests` (incl. `backupOmitsHealthWorkoutsButKeepsDeletedIDsAcrossRestore`) | blocked |
| Sync | `MivuTests/HealthWorkoutSyncTests` | blocked |
| Direct callers | `ProgressStoreTests`, `ProgressInsightsTests`, `CoachReplyLinesTests`, `CoachEngineTests`, `CoachIndexedContextTests`, `CoachBatchTransactionTests`, `DiaryExportConcurrencyTests`, `WidgetSnapshotTests`, `DayProgressActivityTests` | blocked |
| Smoke | `python3 scripts/ci/smoke.py --simulator-id <reserved-UUID>` | blocked |

## Physical phone (owner, real Garmin) — blocked

1. Settings › Diary preferences › Apple Health: connect, and allow workouts and
   active energy. The Garmin Connect app must have Apple Health sharing on.
2. A Garmin activity from today appears in Progress as "from Garmin Connect". Its
   active kcal matches Garmin Connect's active calories, and Today's
   "Exercise-adjusted remaining" rises by that amount.
3. After a new workout, the widget target includes the earned calories without
   opening Mivu (background delivery).
4. Deleting the activity in Garmin Connect, or in Health, removes it from Mivu.
5. Deleting it in Mivu keeps it from being imported again.
6. Wear an Apple Watch and the Garmin on the same session: it is credited once.
7. Tell Coach "I ran this morning" on a day with a Garmin run. Today shows the
   "may have this workout already" warning, and only the Garmin calories count.

## Known gaps

- An iOS export that contains Health workouts doesn't import on Android yet,
  because Android has no `health` burn source.
- Workout detail checks for an overlap only on today's workouts.
- Active calories come from the workout's `activeEnergyBurned` statistics. If
  Garmin writes only the deprecated total energy, workouts show "No calories from
  Health". Step 2 of the phone check will show which one Garmin uses.
