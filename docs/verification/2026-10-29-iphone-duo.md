# iPhone Duo support — verification

Spec: `docs/superpowers/specs/2026-10-29-iphone-duo-design.md`
Plan: `docs/superpowers/plans/2026-10-29-iphone-duo.md`

## Environment

- Xcode 27.1 (App Store), iPhoneOS27.1.sdk. Base: `origin/main` 5afd7931.
- XcodeBuildMCP is not available in this environment; native checks ran with `xcodebuild`, using `-testPlan Mivu SWIFT_VERSION=6.0`, as `scripts/ci/native.sh` does.
- The fold API needs the iOS 27.1 SDK, so `scripts/ci/native.sh` and `signed.sh` now pin `Xcode_27*.app`. This Mac has only `Xcode.app`, so those scripts' selection was checked by their tests, not run natively.

## SDK symbols (iOS 27.1)

- UIKit: `UIView.reservedRegions(kind: UIView.ReservedRegion.Kind, options: UIView.ReservedRegion.QueryOptions = []) -> [UIView.ReservedRegion]`, with kinds `.occlusion` and `.division`, option `.includeInactive`, and `ReservedRegion.isActive`, `.frame` and `.margins`.
- UIKit: `UIHingeInteraction(updateHandler: (UIHingeInteraction, UIHingeInteraction.Update) -> Void)`, where `Update.hinge: UIHinge?` has `UIHinge.status` (`.unknown`, `.closed`, `.partiallyOpen`, `.fullyOpen`) and `angle: CGFloat`.
- SwiftUI: `ArrangementView(primary:secondary:)` with `.arrangementViewStyle(.split / .overlay)` (`@available(anyAppleOS 27.1, *)`); `toolbarVerticalBehavior(_:)`; `defaultAdaptableTabBarPlacement(_:)` with `.sidebar`.

## Results

### First pass: full screen (working tree on base 5afd7931)

- `MivuTests/DuoLayoutTests`: RED first (`cannot find 'DuoLayout' in scope`), then 5/5 pass. iPhone 17 Pro, iOS 27.0 runtime, Xcode 27.1.
- `MivuUITests/DiaryUITests` + `CoachNavigationUITests` on the iPhone 17 Pro: 26/27 pass. The one failure, `DiaryUITests.testRedoSetupFromSettingsKeepsKeyboardNextAndDone`, can't find the `redoOnboarding` button, and fails identically on unmodified `5afd7931` (stashed run). It's pre-existing and not caused by this change.
- iPhone Duo simulator (iOS 27.1 runtime 24A94425), poses driven in Device Hub:
  - Closed (466×678 pt): full screen, no letterbox. `iphone-duo/closed-outer.png`
  - Open (951×669 pt, the default pose is wider than tall): full screen, no letterbox. The system moves the tab bar and profile control into its vertical bar on the right. `iphone-duo/open-sideways.png`
  - Open, rotated upright (669×951 pt): the normal phone layout with the bottom tab bar and one column; Today stayed selected through the rotation. `iphone-duo/open-upright.png`
- Observation: the default open pose is landscape, and the system's vertical bar already acts as a navigation rail there.

### Final pass: source 6faf14c3 on base 5afd7931

Xcode 27.1, iPhoneOS27.1.sdk, local `xcodebuild -testPlan Mivu SWIFT_VERSION=6.0`.

**Normal iPhone: no regression found**

- The app is iPhone-only and portrait-only (`Shared.xcconfig`), so a phone can never be wide: a landscape test on iPhone 17 Pro Max stayed upright.
- Pixel comparison of base and branch, iPhone 17, iOS 27.0, same synthetic fixture. Today, Diary, Progress, Coach, camera, Coach after camera, keyboard, a logged receipt and Today after logging: the layout matches, and the only differing pixels (at most 0.24%) are Pip's blink and glance.
- iPhone 17, iOS 26.5: all of `MivuTests` plus Smoke, RootTabNavigation, Progress, SummaryCards, QuickLog, CoachNavigation, Coach and Diary UI suites: 1341 passed, 16 failed, 1 skipped.
  - 11 `AppleInferenceTests`/`FoodSourceTests`: need iOS 27, not available on this runtime.
  - 4 fail identically on base 5afd7931: `DiaryReportTests.summaryCountsEveryCalendarDayInTheRequestedRange`, `CoachUITests.testFixtureGoalsWeightWorkoutBudgetAndRelaunch`, `CoachNavigationUITests.testLegacyRowAndRepeatedCalendarChoicesKeepExactFirstTurns`, `DiaryUITests.testRedoSetupFromSettingsKeepsKeyboardNextAndDone`.
  - 1, `CompanionSurfaceTests.cameraCoverageRejectsAColdLoadAndConsumedReaction`, failed in the full run and passes alone on both base and branch.
- No normal iPhone runs iOS 27.1 here: that runtime is Duo-only, so `reservedRegions` wasn't exercised on a phone.

**iPhone Duo (iOS 27.1, 24A94425)**

- Book pose: `DuoLayoutTests` + `CoachChatLayoutTests` + `DuoLayoutUITests`: 17 passed, 4 skipped (upright-only), 0 failed.
- Rotated while half-folded, which is real table pose: `DuoLayoutUITests`: 7 passed, 1 skipped (sideways Diary), 0 failed.
- Book to table and back with a Coach draft: the app stayed open, the draft survived, and receipts laid out to the new width without clipping.
- Real table pose: Coach ends at the crease (373.5 pt view height) with the composer on the flat half.

**Not verified on this source**

- Closed pose and open-flat upright: Device Hub only; last checked before these commits.
- Device Hub fold/unfold with a draft: earlier pose changes there closed the app, with no crash report. Rotation doesn't.

**Known limits**

- Coach timeline rows stay 84 pt narrower than the composer in Book pose and sideways; three fixes failed and were reverted.
- Progress's chart card is taller than the standing half in table pose, so its bars need a scroll.
- The crease split has no automated test because a forced posture has no real crease.

**After review, source f739d4f6**

- The independent review found nothing blocking and no path that changes a normal iPhone. Its two cheap findings were fixed: the shutter is disabled during the table timer, which re-checks before firing, and a later change clears the live-day highlight. There's no automated test for the timer race, because the simulator has no camera.
- Duo table pose: `DuoLayoutUITests` 7 passed, 1 skipped. Book pose: `DuoLayoutTests` + `DuoLayoutUITests` passed, with 4 upright-only skips, 0 failed.
- iPhone 17, iOS 27.0: `SmokeUITests`, `RootTabNavigationUITests` and `QuickLogUITests`: 6 passed.
- Deferred, cosmetic and Duo only: entering or leaving table pose drops keyboard focus (the draft stays), and switching Progress or Today layouts resets scroll position.

### Final source 6bfa555a on base 5afd7931

A rotation walkthrough with the on-screen keyboard found four Duo-only bugs that hardware-keyboard runs had hidden. All are fixed:

- Upright, the keyboard shortened the measured view, so the app flipped to the sideways split. `DuoLayoutRoot` now measures the whole window. `testUprightKeyboardKeepsOneColumn` failed, then passed.
- In table pose the composer sat centred on the flat half: it left a large gap, and a tall one slid under the tab bar. It's now bottom-aligned. `testTableComposerRestsOnTheTabBar` failed at 95 pt, then passed.
- In table pose the keyboard hid the field. The split stops following the crease while typing, and Coach's background covers the band the keyboard leaves. `testTableKeyboardKeepsTheFieldVisible` failed with the field at 650 pt against a keyboard top of 560 pt, then passed.
- Moving through the tabs and rotating could hang the app at 100% CPU: a process sample showed `DuoSplit.fold.setter` in the update cycle. Panes now report zero minimums at a crease, so an oversized pane can't move the split. There's no deterministic test: the hang didn't reproduce on demand, so this rests on the sample, and on idle CPU through a full walkthrough of all four rotations afterwards, run on the commit before the final gating.

Also changed: the live-day task returns early outside the Coach side pane; the "Just updated" text is a hint, so it can't replace `MealRow`'s "Needs review" value; `native.sh` and `signed.sh` pin `Xcode_27*`.

**Results on this source**

- iPhone Duo, iOS 27.1, half-folded: `DuoLayoutUITests` upright 10 passed, 1 skipped (sideways Diary); sideways 4 passed, 7 skipped (upright only). `DuoLayoutTests` 12 passed.
- iPhone 17 Pro, iOS 27.0: Smoke, RootTabNavigation and QuickLog 5 passed, 1 failed; `DuoLayoutTests` 12 passed. The failure, `SmokeUITests.testOfflineCaptureSurvivesRelaunchAndNavigation`, hit the 1-minute limit after tapping Send. Rerun alone with a CPU watcher, it passed 3 of 3 with no spike, and it passed on the previous commit, so it's treated as a one-off timeout, not proven as one.
- `python3 -m unittest discover -s scripts/ci -p 'test_*.py'`: 42 passed.

**On the previous commit only**

- iPhone 17 Pro, iOS 27.0: `CoachNavigationUITests` and `CoachChatLayoutTests` passed.
- Screens against the previous build: Today was pixel-identical; Coach differed in 1.33% of pixels, in Pip's pose and the status bar area, with no layout change. The final gating then put normal iPhones back on the original frame path.

**Review:** an independent review of these commits found nothing blocking. Its one change, limiting the zero minimums to a crease so normal iPhones keep the original frames, is applied.

**Closed pose (466×678 pt), same app source, Device Hub:** `DuoLayoutUITests` 4 passed, 7 skipped (they need the inner display); `DuoLayoutTests` 12 passed. Full screen and one column on all four tabs, and typing with the on-screen keyboard keeps the field above it. The system places the tabs in the vertical bar beside the camera. Three tests first failed because they assumed a taller window, so they now scroll to Weight or skip in Closed; the app code didn't change.

**Open flat, app source 7515c1d0, Device Hub:** upright `DuoLayoutUITests` 9 passed, 2 skipped; sideways 4 passed, 7 skipped, in 3 of 4 runs; `DuoLayoutTests` 12 passed. iPhone 17 Pro iOS 27.0: Smoke, RootTab and QuickLog 6 passed, 12 unit passed. By hand, all four tabs in both directions; typing with the on-screen keyboard keeps the field above it, and a draft and the keyboard survive rotating upright to sideways. Sending from there updates the live day.

- Sideways, the Today and Diary section headers sat 20 pt left of their cards. A shared header now sets the inset on wide layouts only, so phones keep the system default. Checked on screenshots, because the accessibility frame reports the whole header row, not the text, so there is no automated test.
- The Closed skip in `testSidewaysTodaySplitsSummaryAndMeals` tested height and also skipped the sideways inner display. It tests width now and passes there.
- One sideways run failed `testTableCameraKeepsShootingUntilDone`: the app stalled 60 seconds in launch with `--duo-posture-ui-test table`, then wasn't running, with no crash report. It didn't recur in 15 launches of that configuration at idle CPU or 3 more suite runs. App CPU during the stall wasn't captured, so a return of the crease layout hang can't be ruled out. Table pose only exists upright, so that launch skips sideways.

**Not verified:** Fold/unfold in Device Hub with a draft is untested. The full 9-screen comparison and the iOS 26.5 regression weren't repeated. VoiceOver wasn't exercised.

**Known limit:** at accessibility text sizes the table composer can overflow upward past the crease.
