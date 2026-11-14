# Language readiness (step 1): verification

Spec: [languages design](../superpowers/specs/2026-11-14-languages-design.md).
Plan: [step 1 plan](../superpowers/plans/2026-11-14-languages-step1-ready.md).

## Source and environment

- Tested source: `dc6683ac`. The app, widget and shared code are identical to
  `9baab4d5`; `dc6683ac` changes only the sweep test.
- Xcode 27.2 (27B52), `SWIFT_VERSION=6.0`, local `xcodebuild` (XcodeBuildMCP was
  not available in this session).
- Simulators: iPhone 17, iOS 26.5; iPhone 18 Pro, iOS 27.0 (a dedicated
  simulator); iPhone Duo, iOS 27.1 (24A94425). Duo poses were set with the
  device tool's `fold` command (hinge 0°, 130°, 180°).

## What changed for people

Nothing visible in English. Every screen was captured before any change
(`languages/baseline/`) and again after removing the English lock; at most
0.25% of pixels differed per screen (edge resampling), with identical layouts.

- English is the only bundled language. A phone set to Hebrew still gets the
  whole app in English, left to right (`testHebrewPhoneGetsEnglish`).
- All text a person reads is in the string catalogs: 1,153 app keys, 34 widget
  keys, 4 App Shortcut phrase sets, 3 permission prompts.
- Layouts mirror under right-to-left; charts keep time left to right.
- Text a person types, or Pip writes, aligns by its own language.
  `typed-hebrew-before.png` shows the second line of a Hebrew message hugging the
  left on an English phone; `typed-hebrew-after.png` shows it right-aligned.
- Coach's number check now reads digits in any script. Before this change a
  reply written with Arabic-Indic digits passed the check unchecked. Save claims
  are detected through a language-independent marker, with the English phrase
  check kept as a second net.

## Results

| Suite | Result |
|---|---|
| `LanguageSweepUITests` on iPhone 17: `english` and `rtl` at default and largest text, `double` at default | every run passed; `testTextIsLocalized` enforces all 12 screens |
| The same matrix on iPhone 18 Pro, plus `testChartsDoNotMirror`, `testRightToLeftFlagMirrorsTheApp`, `testTypedHebrewKeepsItsDirectionAndBytes` (english and rtl), `testHebrewPhoneGetsEnglish`, `testPrimaryActionsStayHittable` (rtl, largest) | every test passed |
| Duo closed (outer screen, upright): `english`, `rtl`, `double`, plus `rtl` at largest text | all passed |
| Duo book (half-open) and open sideways: Today, Diary, Progress and Coach captured in `english`, `rtl` and `double` | reviewed: splits mirror, chart time stays left to right, text fits |
| `TextDirectionTests` | 1/1 (failed first: `TextDirection` missing) |
| `LanguageTextTests` | 10/10 |
| `CoachReplyCheckTests` + `CoachEngineTests` | 69/69; with the marker or the digit mapping disabled, 3 new tests fail (5 issues) |
| Coach unit suites (ReplyCheck, Engine, CorrectionJourney, ReceiptFeedback, Reply, ManualEngine, IndexedContext) | 119/119 |
| Progress unit suites (Insights, Analytics, LanguageText) | 50/50 |
| Notification, Siri, Live Activity, widget snapshot and report suites | 63/64 (below) |
| UI suites: Smoke 1/1, RootTabNavigation 3/3, Diary 23/23, SummaryCards 2/2, Progress 9/9, Companion 16/16, CoachReply 5/5, QuickLog 3/3, QueuedSiri 2/2, LiveActivity 1/1 | all passed |
| CoachUITests 14/15, CoachNavigationUITests 4/5 (Jump to latest drag and tap pass) | failures below |
| `MivuTests`, full | 1,341 tests; only the failures below |
| `scripts/ci/test_languages.py` + `test_workflow_contract.py` | 21/21 |
| `python3 scripts/ci/languages.py check` | exit 0 over 4 catalogs |

Failures that are not caused by this change:

- `DiaryReportTests.summaryCountsEveryCalendarDayInTheRequestedRange`,
  `CoachToolsFixtureTests.fixturesMatchCurrentDeclarationsAndFingerprints`: fail
  identically on the base `3824a898` (run here).
- `CoachUITests.testFixtureGoalsWeightWorkoutBudgetAndRelaunch`,
  `CoachNavigationUITests.testLegacyRowAndRepeatedCalendarChoicesKeepExactFirstTurns`:
  listed as failing on base in the [iPhone Duo record](2026-10-29-iphone-duo.md).
- 11 `AppleInferenceTests`/`FoodSourceTests`: need the iOS 27 on-device model;
  this unit run used iOS 26.5.
- `ManualNutritionUITests.testManualFormSupportsLightDarkAndLargestTextSave`
  fails 1 run in 4 on the base `3824a898` as well (same "Could not reveal mealRow").
- `PipRigViewTests`, `CompanionSurfaceTests`, `CoachCameraTests` and
  `LoopbackCallbackTests` cases fail only under full-suite load and pass when run
  alone (32/32).

## Captures

`languages/step1/` holds contact sheets: `iphone17-*`, `iphone18pro-*`,
`duo-closed-*` (all 12 screens), `duo-book` and `duo-open-sideways` (four tabs
in english, rtl and double), and the typed-Hebrew pair.

## Not verified

- **Duo open upright and table pose.** XCTest cannot turn the Duo's inner screen
  upright (as the earlier Duo record also found), and the device tool has no
  rotation, so those captures repeated the sideways layout and are not counted.
  The closed pose covers the upright single-column layout.
- **Duo open poses through XCTest.** XCTest photographs the outer panel only, so
  open-pose captures were taken with the device tool while a test held the app
  open (`testHoldForCapture`).
- **Fold and unfold with a draft**, VoiceOver on a device, and Siri phrases on a
  device: physical checks, not done.
- **The save marker with the live model**: fixtures prove the engine handles it;
  whether the model writes it reliably belongs to the step 2 live check.
- **Widgets and the Live Activity under right-to-left**: their text is in the
  catalogs and the lint checks it, but they were not captured on a Home Screen.
