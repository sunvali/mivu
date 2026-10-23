# Progress insights verification

- Spec: [2026-10-23-progress-insights-design.md](../superpowers/specs/2026-10-23-progress-insights-design.md)
- Plan: [2026-10-23-progress-insights.md](../superpowers/plans/2026-10-23-progress-insights.md)
- Branch: `feat/progress-insights`, from `main` `f66b8896`.
- Environment: local XcodeBuildMCP, Xcode 27.0, iPhone 18 Pro Max simulator `B82744D2-B0F6-431F-B392-14A0F6868677` on iOS 27.0, `Mivu` test plan.
- Native checks are local only. Hosted CI runs scripts and title checks only.

## Results on the final source (after the review fix pass)

**Units: 150/150 passed.** Suites:
- `ProgressInsightsTests`
- `ProgressAnalyticsTests`
- `ProgressEditorStateTests`
- `CoachBatchTransactionTests`
- `CoachStoreTests`
- `DiaryProjectionIntegrationTests`

They cover:
- Bands, partial and pending days, trend smoothing, the slope-based headline and burn, wins, buckets, and Week judged on the loaded month.
- The 91- and 365-day display ranges, with the Coach still rejected at those lengths.
- A 365-day load under 1 s on the simulator.
- `topFoods` and `hasDays(before:)`.

**UI tests: `ProgressUITests`, `SummaryCardsUITests` and `RootTabNavigationUITests`.**
- First run: 13/14 passed.
- `testFilledGoalLabelsAndClearingLastTargetSurviveRelaunch` failed in the shared `reveal` hit-test helper ("Interactive rows must be fully clear of fixed bars"). It passed on an isolated rerun (1/1), and it had also passed in the run before the fix pass. Treat it as timing-sensitive, not proven stable.

**Smoke (`scripts/ci/smoke.py`, 120 s cap).**
- One run failed at the Coach send step, before Progress is opened. The machine's load average was about 30.
- The rerun passed in 56.4 s.
- This was run before the review fix pass.

**Screenshots.** `ProgressUITests/testChartCardsRenderForEveryRange` and `testEachCardOpensItsDetail` attach screenshots of Week, Month, 3M and Year plus every detail screen, using the synthetic `--diary-progress-fixture`. They were reviewed by eye against the approved mockup.

## Review

One fresh whole-branch review was done, with Ponytail review values. There were no Critical findings. The Important findings were fixed, each with a test that failed first:
- **Partial and pending days were banded and counted.** They now get no band and are drawn lighter. Test: `partialAndPendingDaysGetNoBandAndStayOutOfTheHeadline`.
- **Week could never show a burn.** Loads now cover at least 30 days, and the cards show only the selected range. Test: `weekShowsSevenDaysButJudgesBurnAndWeightOnTheLoadedMonth`.
- **The smoothed trend lagged, so the headline and burn were biased.** Both now use a least-squares slope of the raw weigh-ins. Tests: `steadyLossReadsOnTrackDespiteTheSmoothedLag` and `burnUsesTheWeighInSlopeNotTheLaggingTrend`.
- **Detail screens showed the old window under the new dates.** A window is now shown only when the data belongs to it. This is not covered by an automated test because the race could not be reproduced deterministically.
- **Earlier stopped at the first empty window.** It now pages until `hasDays(before:)` finds no older day. Test: `historyBeforeLooksPastEmptyWeeks`.
- **The protein streak broke on today's unfinished day.** Test: `proteinStreakIgnoresTodayWhileItIsUnfinished`.

## Not covered

These minor findings were deferred and not fixed:
- The snapshot is recomputed on every view update.
- 3M and Year make 14 and 13 partial buckets, where the spec says 13 and 12.
- Top foods:
  - Meals still being re-analyzed count at their old values.
  - Name grouping folds case for ASCII letters only and doesn't collapse inner spaces.
- The detail screen's error path does not check the profile.
- Pip is not re-applied when the theme or reduced motion changes.
- At accessibility text sizes, the weight and burn number rows may truncate.
- Year loads run inside the store actor, and performance has been measured on the simulator only.

Also not checked:
- On-device performance and appearance on an iPhone.
- VoiceOver and Audio Graphs, beyond the accessibility values and labels in the code.
