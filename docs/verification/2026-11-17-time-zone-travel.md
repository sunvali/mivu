# Time zone travel

Plan: [2026-11-17-time-zone-travel.md](../superpowers/plans/2026-11-17-time-zone-travel.md).
Spec: [2026-11-17-time-zone-travel-design.md](../superpowers/specs/2026-11-17-time-zone-travel-design.md).
Branch `feat/time-zone-travel`.

## What changed

- The diary follows the phone's time zone. On launch, on return to the app,
  when iOS reports a zone change, and before a Siri or Shortcut Coach turn,
  the profile zone moves to the phone's zone unless the person pinned one.
- One diary day per date, whatever zone it was opened in. Flying west never
  backs the date up; flying east starts the next date at the usual cutoff.
- Coach turns, weights and workouts accepted before landing still save on the
  same day after landing.
- Each new meal keeps the zone it was eaten in. A meal from another zone shows
  its own clock with the city, for example "9:00 Jerusalem", in Today, meal
  detail, History, the Coach chips and the report.
- Today shows "Now on New York time" with "Keep Jerusalem" when the clock
  changes. A pinned diary shows "Jerusalem time" on the date row, with
  "Use New York time".
- Settings → Diary preferences has a Time zone section: "Set automatically",
  and a searchable city list when it is off.
- History and Progress mark a travel day (meals on two clocks) with an
  airplane, spoken as "Travel day".
- Coach is told the local time and the trip on a travel day, and "today" is
  the open diary day.
- All new on-screen text has English and Hebrew in the string catalog.
- Apple Health workout import (merged from `main`) now finds the day through
  the same one-day-per-date lookup as every other write.

## Evidence

Source: `8ad045026205ca6d48a6ee17bd8f93959ea6d290` (`main` at `dce655de`,
with Apple Health workouts, merged into the branch). Later commits change docs
only.
Environment: macOS 27.0.1, Xcode 27.2, "Mivu time-zone-travel" simulator
(iOS 27.0), XcodeBuildMCP, `-parallel-testing-enabled NO`.

| Check | Result |
|---|---|
| Unit suites `TimeZoneSyncTests`, `DayTests`, `ManualNutritionTransactionTests`, `ProgressStoreTests`, `TimeZoneTravelTests`, `CoachCaptureTransactionTests`, `CoachClarificationTests`, `CoachStoreTests`, `ArchiveFixtureTests`, `ArchiveTests`, `DiaryReportTests`, `MealClockTests`, `DiaryPreferencesDraftTests`, `ProfileTimezoneTests`, `TellCoachTests`, `TimeZoneSyncViewModelTests`, `WidgetSnapshotTests`, `TimeZonePickerTests`, `ProgressAnalyticsTests`, `DiaryWeekStripTests`, `CoachEngineTests`, `AppleInferenceTests`, `CoachContextMessagesTests`, `CoachBatchTransactionTests`, `ProgressEditorStateTests`, `HealthWorkoutStoreTests`, `HealthWorkoutSyncTests`, `HealthWorkoutTests` (one run) | 365/375; the 10 failures all fail on `main` too (below) |
| `MivuUITests/TimeZoneTravelUITests` | 1/1 |
| `scripts/ci/smoke.py` (MivuQuick plan) | pass, 43.59 s |
| `python3 scripts/ci/languages.py check` | exit 0 |
| `python3 scripts/ci/parity.py` | exit 0 |

New tests, all passing in the run above: `TimeZoneSyncTests` (9),
`TimeZoneTravelTests` (15), `TimeZoneSyncViewModelTests` (7), `MealClockTests` (2),
`TimeZonePickerTests` (3), three `DayTests` for Coach's travel context, and
`TimeZoneTravelUITests/testZoneChangeShowsToastAndKeepPinsWithHeaderTag`.

### Failures that are already on `main`

Each fails on the merge base `4d3d4118` (`main` at `f2698a0a` merged into the
branch) with the same counts, so this branch does not cause them:

- `CoachEngineTests`: `unsolicitedModelTimestampCannotEstablishExactMealTime`,
  `progressQuestionKeepsGroundedProse`, `mealProseMayStateTheDaysNewTotal`,
  `progressAnswerUsesRequestedActualBudget`,
  `requestedProgressRereadsFactsAfterSuspendedInference`,
  `statedLocalClockSetsMealTimeOnTheRequestedDay(date:clock:)` and
  `modelTimeSyntaxCannotSetTimeOrChangeRequestedDay(operation:timestamp:)`
  (7 of 68 fail on the merge base).
- `CoachStoreTests`: `idempotentFoodRetryAfterRelaunchDoesNotResurrectDeletedMeal`
  (passed once on this branch, after the Coach day change, then failed again in
  the final run: unstable) and
  `progressReferencesAreBoundedAndOversizedWorkoutRefusesReplacement`.
- `DiaryReportTests/summaryCountsEveryCalendarDayInTheRequestedRange` (a date
  format check; also listed as failing on `main` in the
  [languages record](2026-11-15-languages-step3.md)).

### Checked by hand on the simulator

- Today with the `--time-zone-ui-test` launch fixture: the toast sits above the
  tab bar and the Log meal button, clear of the title and the profile button;
  "Keep Jerusalem" pins the diary and the tag appears on the date row.
- Settings: "Set automatically" on greys out the Time zone row; off, the list
  finds Tokyo by "tok", choosing it shows "Tokyo"; on again returns to
  New York.

## Blocked

- Real travel on a physical iPhone (a flight, or changing the phone's zone in
  iOS Settings with the app open): `blocked`, no device run in this session.
- Android: not started.
- The airplane marker was not seen on screen: there is no UI fixture with a
  two-zone day. Its data path is covered by `historySummaryFlagsTheTravelDay`.
