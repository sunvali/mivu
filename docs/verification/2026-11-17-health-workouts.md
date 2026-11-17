# Workouts from Apple Health — verification

- Branch: `feat/health-workouts`, with `main` @ `f2698a0` merged in.
- Environment: macOS 27.0.1 and Xcode 27.2 (27B52). The simulator was a dedicated
  iPhone 17 Pro on iOS 26.5, `C9C051B0-1AA2-4A8B-BA70-8C996FFAA35B`. DerivedData was
  `build/DerivedData` in this worktree. Runs used the XcodeBuildMCP CLI, test plan
  `Mivu`, suite `-only-testing` selectors, and no parallel testing.

## Results (2026-11-17, after merging main)

Unit suites ran at `375af329`, the merge with main plus the Hebrew strings. Review
fixes followed in `0b0e838b`. They change only Health import code:
`HealthWorkoutSync.disconnect` keeps its anchor, and `applyHealthWorkouts` stores
0 kcal as unknown. At `0b0e838b`, the two Health suites, smoke and the script checks
ran again.

| Run | Scope | Source | Passed | Failed | Result |
|---|---|---|---|---|---|
| Build | `Mivu` scheme, Debug, iOS simulator | `375af329` | — | — | pass (0 errors) |
| Model | `HealthWorkoutTests` | `375af329` | 4 | 0 | pass |
| Store import | `HealthWorkoutStoreTests` (incl. `zeroCaloriesAreStoredAsUnknown`) | `0b0e838b` | 10 | 0 | pass |
| Sync | `HealthWorkoutSyncTests` (incl. `reconnectResumesFromSavedAnchorSoDeletionsArrive`) | `0b0e838b` | 5 | 0 | pass |
| Credit rule | `ProgressAnalyticsTests` | `375af329` | 20 | 0 | pass |
| Progress store | `ProgressStoreTests` | `375af329` | 13 | 0 | pass |
| Insights | `ProgressInsightsTests` | `375af329` | 32 | 0 | pass |
| Coach privacy | `CoachStoreTests` (incl. `coachNeverSeesHealthWorkouts`) | `375af329` | 46 | 3 | fails the same as `main` |
| Coach engine | `CoachEngineTests` | `375af329` | 61 | 7 | fails the same as `main` |
| Coach lines | `CoachReplyLinesTests` | `375af329` | 9 | 3 | fails the same as `main` |
| Coach batch | `CoachBatchTransactionTests` | `375af329` | 23 | 1 | fails the same as `main` |
| Coach context | `CoachIndexedContextTests` | `375af329` | 17 | 0 | pass |
| Backup | `ArchiveTests` (incl. `backupOmitsHealthWorkoutsButKeepsDeletedIDsAcrossRestore`) | `375af329` | 35 | 0 | pass |
| Export | `DiaryExportConcurrencyTests` | `375af329` | 28 | 0 | pass |
| Services | `MivuServicesTests` | `375af329` | 1 | 0 | pass |
| Widget | `WidgetSnapshotTests` | `375af329` | 5 | 0 | pass |
| Live Activity | `DayProgressActivityTests` | `375af329` | 20 | 0 | pass |
| Diary | `DiaryTests` | `375af329` | 30 | 0 | pass |
| Languages | `LanguageTextTests`, `HebrewSurfaceTextTests` | `375af329` | 16 | 0 | pass |
| Smoke | `python3 scripts/ci/smoke.py --simulator-id C9C051B0-…` | `0b0e838b` | 1 | 0 | pass (74.1 s) |
| Scripts | `scripts/ci/languages.py check`, `scripts/ci/parity.py` | `0b0e838b` | — | — | pass |

**The 14 Coach failures come from `main`, not this branch.** The same four suites
ran on `main` @ `f2698a0` with the same simulator. They failed the same 14 tests
(138 passed, 14 failed). The failures expect the requested day `2027-01-15` and get
`2027-01-14`, or they read "There's no food recorded". That points to a dependence
on the clock or the time zone.

Before the merge, `4d2149b7` on base `720cc3f` had 278 passed and 9 failed. The base
itself had the same 9 Coach failures.

The new strings have Hebrew translations, following `docs/languages/he.md`. The
owner hasn't reviewed them yet. Not run: the full UI test suite and the language
capture sweep. The plan's "Expected: FAIL" steps stay unticked, because no failing
run was observed. Task 2 step 5 (`CoachReplyLinesTests`) and Task 4 step 4 stay unticked
until the Coach failures on `main` are fixed.

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
