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

## After the whole-branch review

An independent review found five issues, fixed in `fix(languages): …` on top of
`ad5f0485`, each with a test that failed first:

- Diary and Progress dates followed the phone's calendar and digit settings
  (a Hebrew or Buddhist calendar, Arabic-Indic digits), and the day name reaches
  Coach. Dates are now always Gregorian with 0–9 (`datesStayGregorianWithLatinDigits`).
- The save marker made Coach drop the model's reply after every weight or
  workout save (`markedWeightReplyKeepsTheModelsProse`).
- The marker rule now applies only to saves made in this turn, so "yes, breakfast
  is logged" about an earlier save no longer fails the turn.
- The marker is matched loosely (`<saved />`, `<Saved/>`, in backticks), so it
  never shows in the chat (`markerSpellingsAreAllStripped`).
- "1 weigh-ins" now reads "1 weigh-in"; weigh-ins, minutes, days logged, photos,
  tracked days and "times" use plural forms, and "once · …" in Top foods became
  translatable (`oneWeighInReadsSingular`, `convertedCountsKeepTheirEnglish`).

Re-run on the iPhone 18 Pro (iOS 27.0) after the fixes: `MivuTests` 1,356 tests
with only the base and load-only failures listed above (the on-device Apple model
tests pass on iOS 27); Smoke, Progress, CoachReply and Companion UI 31/31;
`testTextIsLocalized` (double), `testEveryScreenOpens` and `testChartsDoNotMirror` (rtl) pass.

## After the specialist reviews

A localization engineer review (74/100) and a Hebrew user review (72/100) raised
step 1 items, fixed in `fix(languages): whole sentences per workout kind …`:

- Workout lines, deletion titles and "Workout saved" are whole sentences per kind;
  the stored raw kind ("cardio") no longer reaches the screen through
  `capitalized` (`workoutLinesAreWholePerKind`). "1 minutes" reads "1 minute".
- The set line ("bodyweight", "repetitions") and the report's fallback "Meal"
  are translatable; "1 repetitions" reads "1 repetition" (`setLinesReadCorrectly`).
- "Today"/"Yesterday" headings come from their own keys, not by capitalizing
  "today"; the band word in the chart summary has its own lowercase keys, and
  the band "Off" was not translatable (`bandWordsReadMidSentence`).
- `languages.py check` now rejects a translation that drops or changes a
  placeholder, and a plural missing a form its language needs (CLDR table for
  ar, he, ru, uk, pl, es, fr, it, pt).

Deferred to step 2 or the language that needs it: comment coverage for short
keys (only the new ones have comments), comma decimals in the reply check,
digit style for numbers in Arabic, first-letter alignment of mixed messages,
and the chart direction question.

Re-run on the iPhone 18 Pro (iOS 27.0): 7 affected `MivuTests` suites, 117/118
(the one failure is the base `summaryCountsEveryCalendarDayInTheRequestedRange`);
`testTextIsLocalized` (double) passes; `testEveryScreenOpens` (double) failed once
waiting for the Coach receipt, passed on base and on a rerun of this change.
`test_languages.py` 17/17.

## Captures

`languages/step1/` holds contact sheets: `iphone17-*`, `iphone18pro-*`,
`duo-closed-*` (all 12 screens), `duo-book` and `duo-open-sideways` (four tabs
in english, rtl and double), and the typed-Hebrew pair.

## Simulator checks after the PR opened

Run on 2026-11-15 on a dedicated iPhone Duo simulator (iOS 27.1) with the
build of `9a68162`, right-to-left pseudolanguage, driven by the device tool
(`fold`, `orientation landscape-left` turns the inner screen upright):

- **Open upright** (`languages/step1/duo-open-upright.png`) and **table pose**
  (`duo-table.png`): Today, Diary, Progress and Coach mirror (tab bar from the
  right, titles and meal rows trailing, Week first in the range control), charts
  keep time left to right, Pip is not flipped except the known Progress card case.
  In table pose Coach hides Pip and moves the controls to the flat half by design
  (`CoachView.atTable`).
- **Fold and unfold with a draft** (`duo-draft.png`): the Hebrew draft
  "2 ביצים ו-toast, קפה עם חלב 3%" kept every character, its right-to-left
  alignment and keyboard focus through open → closed → open. Seen on the way:
  closed and sideways with the keyboard up, Coach's empty-state heading overlaps
  the date divider; a layout issue, not checked against `main`.
- **VoiceOver, partly**: the accessibility tree on all four tabs has a name for
  every control and reads right to left (Today tab first, Week first). Spoken
  output was not heard; one button was printed by the tool as its identifier
  (`todayDayActions`) although the source gives it the label "Day actions, <date>".

The real iPhone Duo (iOS 27.2.1) ran the right-to-left sweep once: charts stayed
left to right; the other three tests failed because the sweep's steps assume the
simulator layout (the real outer screen, 457 × 678 points, uses the side rail
upright and puts Add in the "…" menu). The phone was restored to a `main` build
and its diary checked identical to a backup taken before install.

## Follow-ups from the Duo checks

Source `30f491f` (the tests ran on this tree; a one-line comment was reworded
before the commit). Local Xcode runs with XcodeBuildMCP on two simulators made
for this work: "Mivu duo followups (Claude)" (iPhone Duo, iOS 27.1, closed and
sideways, so the side rail shows as on the real outer screen) and "Mivu duo
followups iPhone (Claude)" (iPhone 17, iOS 27.0). Not hosted CI.

- **Coach empty state over the date row**: `main` has the same code, so it had
  the same problem. The heading and body now show only when their full height
  fits between the day row and the composer, and stay out of VoiceOver when
  hidden. `DuoLayoutUITests/testShortCoachEmptyStateStaysInItsSpace` failed
  first (body 47 points under Pip), then passed on the Duo and on the iPhone 17.
  The empty state still shows on the closed Duo without the keyboard; at the
  largest text there it is hidden because the composer's note already fills the
  screen (an existing layout matter, not changed here).
  `DiaryUITests/testPrecisionGlassReferenceScreensInBothAppearances`, which
  checks the heading on a normal iPhone, passed: 1 of 1. Its runtime warning
  "Invalid frame dimension" also appears on the base commit `50fb54a`.
- **Sweep on the side rail**: with `TEST_RUNNER_SWEEP_MODE=rtl`,
  `testRightToLeftFlagMirrorsTheApp` failed on the Duo as on the real phone
  (both tabs at x = 418). The side rail stays on the screen's right edge in both
  directions, so for a vertical rail the test now checks that the screen beside
  it mirrors (the "Today" title sits right of centre). Bar items go through one
  helper that opens "…" when an item is folded away (Add and Chat history), and
  the Coach field is tapped until it has the keyboard. `testEveryScreenOpens`,
  `testRightToLeftFlagMirrorsTheApp` and `testTypedHebrewKeepsItsDirectionAndBytes`
  passed 3 of 3 on the Duo and 3 of 3 on the iPhone 17. The simulator shows Add
  in the rail, so the "…" path did not run; the real outer screen still needs
  one sweep run.
- **Day actions label**: not a bug. XCUITest reads `todayDayActions` with the
  label "Day actions, Your waking day" in both directions; the sweep now asserts
  the label.

## Not verified

- **The save marker with the live model**: needs a ChatGPT sign-in on the test
  simulator, not done yet. Fixtures prove the engine handles the marker.
- **Siri phrases**: Siri does not run on the simulator.
- **VoiceOver speech and the Duo split-screen with another app**: real-device checks.
- **Widgets and the Live Activity under right-to-left**: their text is in the
  catalogs and the lint checks it, but they were not captured on a Home Screen.
- **The sweep on the real Duo's outer screen**: it now handles the side rail and
  the "…" menu, but has not been run on the phone again.
