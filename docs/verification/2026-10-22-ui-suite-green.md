# Full UI suite green and bounded — verification

- **Source:** branch `fix/ui-suite-green` on `main` `d2b0fecd`; the full runs below tested `bd5f5951` (test and code changes), followed by this record and doc-only edits.
- **Environment:** Xcode 27.0 (27A266a), macOS 27.0.1. A dedicated iPhone 17 Pro simulator on iOS 26.5 (`AD31AE8A-0DBA-476B-95B3-A8BA4B8EC47A`), plus an iPhone 18 Pro on iOS 27.0 (`3FA338E1-8888-48B5-B23E-9F7221FA037D`) for the VoiceOver tests that skip below iOS 27. Other agents' native runs were active on the Mac throughout. `xcodebuild` ran directly because XcodeBuildMCP was not available as a tool in this session.
- **Flags:** `-testPlan Mivu -parallel-testing-enabled YES -parallel-testing-worker-count 3 -collect-test-diagnostics never` for UI; units ran serially.

## Results

| Run | Revision | Result |
|---|---|---|
| Baseline `-only-testing:MivuUITests`, 120 s allowance | `d2b0fecd` | 91 passed, 14 failed, 2 skipped (28 min) |
| Same 14 tests, 300 s allowance | `d2b0fecd` | 6 passed (load/timeout only), 8 failed deterministically |
| `-only-testing:MivuUITests` | `bd5f5951` | **105 passed, 0 failed, 2 skipped** (32 min) |
| The 2 iOS 27 VoiceOver tests (iOS 27.0 simulator) | `bd5f5951` | `testSpikePagingPreservesAccessibilityFocus` passed; `testVoiceOverReachesHistoryPagingControl…` failed once with `AXVoiceOverAutomationErrorDomain` "Failed to send moveBackward command", then passed alone |
| `-only-testing:MivuTests` | `bd5f5951` | **1114 passed, 0 failed, 1 skipped** (`nativeAuthenticationBrowserReachesLoopback`, 169 s) |

After rebasing on `c987be1a` (#46, floating Coach composer), `CoachHistoryUITests.testRealScrollAutomaticallyPagesAndStopsAtExhaustion` failed on `main` itself: its reverse `swipeUp()` landed on the check-in card floating over the viewport. It now drags at 30% height, as #46 did for the other helpers. `CoachHistoryUITests`, `CoachUITests` and `CompanionUITests` then passed: **37 passed, 0 failed**.

## Causes and fixes

| Test | Cause | Fix |
|---|---|---|
| `DiaryUITests.testCalendarJumpSelectsDate` | **App:** with the inline-large "Diary" title, the leading Choose date item collapsed into a system "More" overflow | Choose date joins the trailing toolbar group |
| `DiaryUITests` capture/photo viewer, `ManualNutritionUITests` offline append | `isHittable` stays true under the pinned Log meal / Ask Pip bars, so taps on meal rows and Add food manually hit the bar | Reveal rows clear of those bars before tapping (pattern from `DiaryAmountEditorUITests`) |
| `ManualNutritionUITests` cancel and largest text | The form does not scroll a field out from under the keyboard; at accessibility sizes the stacked bottom bar covers the screen centre where the helper swiped | Close the keyboard with Done; drag in the upper list |
| `ManualNutritionUITests.testManualFormSupportsLightDarkAndLargestTextSave` | The edge tap was 21 pt from the centre of Save, whose iOS 26 toolbar frame is 36 pt | Tap 4 pt inside the frame edge |
| `CoachHistoryUITests.testReceiptShowsCommittedDateAndUnknownEstimates` | The Diary quote focuses the composer; with the keyboard up the viewport is ~110 pt | Drag the keyboard away before revealing the receipt |
| `ProgressUITests.testSavedWorkoutSetsAndNoGoalReport` | Ran at 02:00: the meal went to the 21 Oct waking day, the weight started 22 Oct, and the Day report followed 22 Oct | Launch with `-dayStartHour 0` (an XML integer, so `DayCutoff.hour` reads an `Int`) |
| 6 others | 120 s allowance under three clones; passing tests reach 117 s | Allowance 300 s, cap 600 s |

A fresh simulator also showed the iOS swipe-typing introduction over the keyboard. Marking it as shown fixed that; `docs/development/ci-cd.md` has the commands.

## Open product questions (not changed)

- The manual-nutrition Save/Cancel toolbar buttons report a 36 pt frame despite `minHeight: 44`. The system glass toolbar clamps them below the repo's 44-point target rule.
- Between midnight and the day cutoff, a morning weight starts the calendar day while meals stay on the waking day, so Progress' Day report omits that night's meals.
- At accessibility text sizes the stacked Log with Pip / Add manually bar covers most of Today.

## Not verified

Physical device, real VoiceOver use, and the smoke runner (`scripts/ci/smoke.py`).
