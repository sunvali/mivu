# Workouts from Apple Health — verification

- Branch: `feat/health-workouts`. Base: `main` @ `720cc3f`.
- Spec: `docs/superpowers/specs/2026-11-17-health-workouts-design.md`
- Plan: `docs/superpowers/plans/2026-11-17-health-workouts.md`
- Tested source: `4d2149b7c03d389379711b4a08051b15f8742019`. The source didn't change
  for this record. The build compiled with no errors, so no fixes were needed.
- Environment: macOS 27.0.1 and Xcode 27.2 (27B52). The simulator was a dedicated
  iPhone 17 Pro on iOS 26.5, `C9C051B0-1AA2-4A8B-BA70-8C996FFAA35B`. DerivedData was
  `build/DerivedData` in this worktree. Runs used the XcodeBuildMCP CLI, test plan
  `Mivu`, suite `-only-testing` selectors, and no parallel testing.

## Results (2026-11-17)

| Run | Scope | Passed | Failed | Result |
|---|---|---|---|---|
| Build | `Mivu` scheme, Debug, iOS simulator | — | — | pass (0 errors) |
| Model | `MivuTests/HealthWorkoutTests` | 4 | 0 | pass |
| Store import | `MivuTests/HealthWorkoutStoreTests` | 9 | 0 | pass |
| Sync | `MivuTests/HealthWorkoutSyncTests` | 4 | 0 | pass |
| Credit rule | `MivuTests/ProgressAnalyticsTests` | 20 | 0 | pass |
| Progress store | `MivuTests/ProgressStoreTests` | 13 | 0 | pass |
| Coach privacy | `MivuTests/CoachStoreTests` (incl. `coachNeverSeesHealthWorkouts`) | 44 | 4 | fail, pre-existing (see below) |
| Coach engine | `MivuTests/CoachEngineTests` | 49 | 5 | fail, pre-existing (see below) |
| Coach context | `MivuTests/CoachIndexedContextTests` | 17 | 0 | pass |
| Backup | `MivuTests/ArchiveTests` (incl. `backupOmitsHealthWorkoutsButKeepsDeletedIDsAcrossRestore`) | 35 | 0 | pass |
| Export | `MivuTests/DiaryExportConcurrencyTests` | 28 | 0 | pass |
| Services | `MivuTests/MivuServicesTests` | 1 | 0 | pass |
| Widget | `MivuTests/WidgetSnapshotTests` | 5 | 0 | pass |
| Live Activity | `MivuTests/DayProgressActivityTests` | 20 | 0 | pass |
| Diary | `MivuTests/DiaryTests` | 29 | 0 | pass |
| Smoke | `python3 scripts/ci/smoke.py --simulator-id C9C051B0-…` | 1 | 0 | pass (64.9 s) |

Unit total: 278 passed, 9 failed, 0 skipped.

**The 9 Coach failures are pre-existing.** The same two suites, run on the base
commit `720cc3f` with the same simulator, failed the same 9 tests (92 passed,
9 failed). The branch adds one Coach test, `coachNeverSeesHealthWorkouts`, and it
passes. The failures expect the requested day `2027-01-15` and get `2027-01-14`, or
get a different time zone. That points to a dependence on the clock or time zone,
not to this change:

- `CoachEngineTests`: `modelTimeSyntaxKeepsDateOnlyPrecisionAndRequestedDay`,
  `progressQuestionKeepsGroundedProse`, `mealProseMayStateTheDaysNewTotal`,
  `progressAnswerUsesRequestedActualBudget`,
  `requestedProgressRereadsFactsAfterSuspendedInference`
- `CoachStoreTests`: `idempotentFoodRetryAfterRelaunchDoesNotResurrectDeletedMeal`,
  `capturedTimezoneAndExplicitHistoricalTimeSurviveProfileChange`,
  `unconfirmedCoachTimeStaysDateOnlyAndManualCaptureRemainsExact`,
  `progressReferencesAreBoundedAndOversizedWorkoutRefusesReplacement`

Not run in this pass: `ProgressInsightsTests`, `CoachReplyLinesTests`,
`CoachBatchTransactionTests`, and full UI tests. The plan's "Expected: FAIL" steps
stay unticked, because the code was written without a toolchain and no failing run
was observed. Task 2 step 5 and Task 4 step 4 also stay unticked until the suites
listed above run, or the pre-existing Coach failures are fixed.

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
- The deletion query filters by start date. If HealthKit leaves deletions out of a
  date-filtered anchored query, step 4 of the phone check will fail. In that case,
  drop the predicate on the anchored query only.
- Active calories come from the workout's `activeEnergyBurned` statistics. If
  Garmin writes only the deprecated total energy, workouts show "No calories from
  Health". Step 2 of the phone check will show which one Garmin uses.
